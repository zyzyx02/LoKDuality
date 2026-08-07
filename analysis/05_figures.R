## 05_figures.R
## Figures for the Results section.
##
## Run after 01 to 04, from the folder holding the corpus and the out_*.csv
## files. Each figure is written twice, as PDF for the submission and as a
## 600 dpi PNG for inspection.
##
## Usage:  Rscript 05_figures.R

source("lok_common.R")
suppressPackageStartupMessages({
  library(ggplot2)
})

FIGDIR <- "figures"
dir.create(FIGDIR, showWarnings = FALSE)

EMOTIONS <- c("anger", "anticipation", "disgust", "fear",
              "joy", "sadness", "surprise", "trust")

CELL_ORDER <- c("Kain / narration", "Kain / dialogue",
                "Raziel / narration", "Raziel / dialogue",
                "Supporting / dialogue")

## A print-safe palette. Narration darker, dialogue lighter, baseline grey.
CELL_COLS <- c("Kain / narration"      = "#7B3294",
               "Kain / dialogue"       = "#C2A5CF",
               "Raziel / narration"    = "#008837",
               "Raziel / dialogue"     = "#A6DBA0",
               "Supporting / dialogue" = "#8C8C8C")

theme_paper <- function(base_size = 10) {
  theme_bw(base_size = base_size) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          legend.position = "bottom",
          legend.title = element_blank(),
          strip.background = element_rect(fill = "grey92", colour = NA))
}

save_fig <- function(p, name, w, h) {
  ggsave(file.path(FIGDIR, paste0(name, ".pdf")), p,
         width = w, height = h, units = "in", device = cairo_pdf)
  ggsave(file.path(FIGDIR, paste0(name, ".png")), p,
         width = w, height = h, units = "in", dpi = 600)
  message("wrote ", name)
}

need <- function(f) {
  if (!file.exists(f)) stop("missing ", f, ". Run the numbered scripts first.")
  readr::read_csv(f, show_col_types = FALSE, progress = FALSE)
}


## ---------------------------------------------------------------------------
## Figure 1. Emotion profile: share and rate side by side.
## The point of the figure is that the left panel is flat across cells and the
## right panel is not, so the two panels share an x axis but not a y scale.
## ---------------------------------------------------------------------------
fig1 <- function() {
  prof <- need("out_nrc_profiles.csv")
  d <- prof %>%
    select("group", "emotion", "share", "rate100") %>%
    tidyr::pivot_longer(c("share", "rate100"),
                        names_to = "measure", values_to = "value") %>%
    mutate(
      group = factor(.data$group, levels = CELL_ORDER),
      emotion = factor(.data$emotion, levels = EMOTIONS),
      measure = factor(.data$measure, levels = c("share", "rate100"),
                       labels = c("Share of emotion tokens",
                                  "Hits per 100 words")),
      value = ifelse(.data$measure == "Share of emotion tokens",
                     100 * .data$value, .data$value)
    )

  p <- ggplot(d, aes(x = .data$emotion, y = .data$value, fill = .data$group)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.75) +
    facet_wrap(~ measure, ncol = 1, scales = "free_y") +
    scale_fill_manual(values = CELL_COLS) +
    labs(x = NULL, y = NULL) +
    theme_paper() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  save_fig(p, "fig1_emotion_profiles", 7.0, 6.0)
}


## ---------------------------------------------------------------------------
## Figure 2. Forest plot of the primary contrasts.
## Register contrasts on the left, character contrasts on the right. Filled
## points mark intervals that exclude zero.
## ---------------------------------------------------------------------------
fig2 <- function() {
  co <- need("out_nrc_contrasts.csv")
  primary <- list(
    c("Kain / narration", "Kain / dialogue", "Register: Kain"),
    c("Raziel / narration", "Raziel / dialogue", "Register: Raziel"),
    c("Kain / narration", "Raziel / narration", "Character: in narration"),
    c("Kain / dialogue", "Raziel / dialogue", "Character: in dialogue")
  )
  lab <- vapply(primary, function(p) p[3], character(1))
  key <- vapply(primary, function(p) paste(p[1], p[2]), character(1))

  d <- co %>%
    mutate(k = paste(.data$a, .data$b)) %>%
    filter(.data$k %in% key) %>%
    mutate(
      contrast = factor(lab[match(.data$k, key)], levels = lab),
      emotion = factor(.data$emotion, levels = rev(EMOTIONS)),
      measure = factor(.data$measure, levels = c("share", "rate100"),
                       labels = c("Difference in share",
                                  "Difference in hits per 100 words"))
    )

  p <- ggplot(d, aes(x = .data$diff, y = .data$emotion)) +
    geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
    geom_errorbarh(aes(xmin = .data$lo, xmax = .data$hi),
                   height = 0, linewidth = 0.5) +
    geom_point(aes(shape = .data$excludes_zero, fill = .data$excludes_zero),
               size = 2) +
    scale_shape_manual(values = c(`FALSE` = 21, `TRUE` = 21),
                       labels = c("interval covers 0",
                                  "interval excludes 0")) +
    scale_fill_manual(values = c(`FALSE` = "white", `TRUE` = "black"),
                      labels = c("interval covers 0",
                                 "interval excludes 0")) +
    facet_grid(contrast ~ measure, scales = "free_x") +
    labs(x = NULL, y = NULL) +
    theme_paper()
  save_fig(p, "fig2_primary_contrasts", 7.5, 8.0)
}


## ---------------------------------------------------------------------------
## Figure 3. Lexical diversity, full text against a common token budget.
## Two panels make the length artefact visible: the TTR ordering changes when
## the token count is equalised, the MTLD ordering does not.
## ---------------------------------------------------------------------------
fig3 <- function() {
  ld <- need("out_lexical_diversity.csv")
  d <- ld %>%
    mutate(group = factor(.data$group, levels = rev(CELL_ORDER)))

  ttr <- d %>%
    select("group", "tokens", full = "ttr_full", budgeted = "ttr_std") %>%
    tidyr::pivot_longer(c("full", "budgeted"),
                        names_to = "basis", values_to = "value") %>%
    mutate(measure = "Type-token ratio")

  mtld <- d %>%
    select("group", "tokens", full = "mtld_full", budgeted = "mtld_std") %>%
    tidyr::pivot_longer(c("full", "budgeted"),
                        names_to = "basis", values_to = "value") %>%
    mutate(measure = "MTLD")

  both <- bind_rows(ttr, mtld) %>%
    mutate(basis = factor(.data$basis, levels = c("full", "budgeted"),
                          labels = c("full text", "common budget")),
           measure = factor(.data$measure,
                            levels = c("Type-token ratio", "MTLD")))

  rng <- ld %>%
    select("group", ymin = "mtld_std_lo", ymax = "mtld_std_hi") %>%
    mutate(group = factor(.data$group, levels = rev(CELL_ORDER)),
           basis = factor("common budget",
                          levels = c("full text", "common budget")),
           measure = factor("MTLD", levels = c("Type-token ratio", "MTLD")))

  p <- ggplot(both, aes(x = .data$value, y = .data$group,
                        colour = .data$basis, shape = .data$basis)) +
    geom_errorbarh(data = rng,
                   aes(xmin = .data$ymin, xmax = .data$ymax, y = .data$group),
                   inherit.aes = FALSE, height = 0,
                   colour = "grey60", linewidth = 0.5) +
    geom_point(size = 2.6) +
    facet_wrap(~ measure, scales = "free_x") +
    scale_colour_manual(values = c("full text" = "grey55",
                                   "common budget" = "black")) +
    scale_shape_manual(values = c("full text" = 1, "common budget" = 16)) +
    labs(x = NULL, y = NULL) +
    theme_paper()
  save_fig(p, "fig3_lexical_diversity", 7.5, 3.4)
}


## ---------------------------------------------------------------------------
## Figure 4. Cosine similarity matrix over all documents.
## ---------------------------------------------------------------------------
fig4 <- function() {
  m <- need("out_similarity_matrix.csv")
  rn <- m[[1]]
  mat <- as.matrix(m[, -1, drop = FALSE])
  rownames(mat) <- rn

  ord <- c(intersect(CELL_ORDER[1:4], rn), sort(setdiff(rn, CELL_ORDER[1:4])))
  mat <- mat[ord, ord, drop = FALSE]

  d <- as.data.frame(as.table(mat))
  names(d) <- c("a", "b", "cos")
  d$a <- factor(d$a, levels = ord)
  d$b <- factor(d$b, levels = rev(ord))

  p <- ggplot(d, aes(x = .data$a, y = .data$b, fill = .data$cos)) +
    geom_tile(colour = "white", linewidth = 0.3) +
    scale_fill_gradient(low = "#F7F7F7", high = "#2C2C6E",
                        na.value = "white", name = "cosine") +
    coord_fixed() +
    labs(x = NULL, y = NULL) +
    theme_paper() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "right", legend.title = element_text())
  save_fig(p, "fig4_similarity_matrix", 7.0, 6.2)
}


## ---------------------------------------------------------------------------
## Figure 5. Where the four design pairs sit among all 120 pairs.
## ---------------------------------------------------------------------------
fig5 <- function() {
  pairs <- need("out_similarity_pairs.csv")
  key <- list(
    c("Kain / narration", "Raziel / narration"),
    c("Kain / dialogue", "Raziel / dialogue"),
    c("Kain / narration", "Kain / dialogue"),
    c("Raziel / narration", "Raziel / dialogue")
  )
  klab <- c("Kain vs Raziel, narration", "Kain vs Raziel, dialogue",
            "Kain vs Kain", "Raziel vs Raziel")

  marks <- do.call(rbind, lapply(seq_along(key), function(i) {
    k <- key[[i]]
    row <- pairs[(pairs$a == k[1] & pairs$b == k[2]) |
                   (pairs$a == k[2] & pairs$b == k[1]), , drop = FALSE]
    data.frame(label = klab[i], cos = row$cos[1],
               kind = ifelse(i <= 2, "same register", "same character"))
  }))

  ## Label height is computed from the histogram itself. An earlier version
  ## placed the labels at y = Inf, where they were clipped away on export.
  h <- graphics::hist(pairs$cos, breaks = 30, plot = FALSE)
  ymax <- max(h$counts)
  marks$y <- ymax * c(0.95, 0.80, 0.65, 0.50)[seq_len(nrow(marks))]

  p <- ggplot(pairs, aes(x = .data$cos)) +
    geom_histogram(bins = 30, fill = "grey82", colour = "white",
                   linewidth = 0.2) +
    geom_vline(data = marks,
               aes(xintercept = .data$cos, colour = .data$kind,
                   linetype = .data$kind), linewidth = 0.6) +
    ggrepel::geom_text_repel(
      data = marks,
      aes(x = .data$cos, y = .data$y, label = .data$label,
          colour = .data$kind),
      size = 2.8, hjust = 1, nudge_x = -0.004, direction = "y",
      segment.size = 0.2, min.segment.length = 0, show.legend = FALSE) +
    expand_limits(y = ymax * 1.05) +
    scale_colour_manual(values = c("same register" = "#7B3294",
                                   "same character" = "#008837")) +
    labs(x = "cosine similarity", y = "number of document pairs") +
    theme_paper()
  save_fig(p, "fig5_pair_distribution", 7.0, 4.0)
}


## ---------------------------------------------------------------------------
## Figure 6. Full corpus against the Defiance-only replication.
## ---------------------------------------------------------------------------
fig6 <- function() {
  x <- load_corpus()
  source("03_pairwise_similarity.R", local = TRUE)

  contrast_on <- function(d, label) {
    docs <- build_documents(d)
    need4 <- c("Kain / narration", "Kain / dialogue",
               "Raziel / narration", "Raziel / dialogue")
    if (!all(need4 %in% unique(docs$doc))) return(NULL)
    s <- cosine_matrix(tfidf_matrix(docs))
    data.frame(
      corpus = label,
      quantity = c("same register,\ndifferent character",
                   "same character,\ndifferent register"),
      value = c(mean(c(s["Kain / narration", "Raziel / narration"],
                       s["Kain / dialogue", "Raziel / dialogue"])),
                mean(c(s["Kain / narration", "Kain / dialogue"],
                       s["Raziel / narration", "Raziel / dialogue"])))
    )
  }

  d <- bind_rows(
    contrast_on(x, "All five games"),
    contrast_on(x[x$game == "Defiance", , drop = FALSE], "Defiance only")
  )
  d$corpus <- factor(d$corpus, levels = c("All five games", "Defiance only"))

  p <- ggplot(d, aes(x = .data$corpus, y = .data$value,
                     fill = .data$quantity)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6) +
    geom_text(aes(label = sprintf("%.3f", .data$value)),
              position = position_dodge(width = 0.7),
              vjust = -0.4, size = 3) +
    scale_fill_manual(values = c("#7B3294", "#C2A5CF")) +
    expand_limits(y = max(d$value) * 1.15) +
    labs(x = NULL, y = "mean cosine similarity") +
    theme_paper()
  save_fig(p, "fig6_defiance_replication", 6.0, 4.0)
}


main <- function() {
  fig1(); fig2(); fig3(); fig4()
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    fig5()
  } else {
    message("skipping figure 5: install ggrepel, or replace the repel layer ",
            "with geom_text")
  }
  fig6()
  message("figures written to ", normalizePath(FIGDIR))
}

if (sys.nframe() == 0) main()
