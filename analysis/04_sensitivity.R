## 04_sensitivity.R
## Do the conclusions survive if the classifier-assigned register labels are
## treated as unreliable?
##
## Roughly 42 per cent of the words in the corpus carry a register label that
## came from the logistic classifier rather than from an explicit marker in
## the source transcript, from the narrator constraint, or from hand coding.
## A reviewer will ask what happens if those are wrong. This script recomputes
## the headline measures on three nested versions of the corpus.
##
##   full       every block
##   confident  classifier blocks dropped when the predicted probability sits
##              inside a band around the decision boundary
##   strict     every classifier block dropped, leaving only labels from the
##              source transcripts, the narrator constraint and hand coding
##
## If an ordering or a sign flips between full and strict, the finding rests
## on the classifier and must be reported with that caveat. If it holds, the
## classifier is doing no load-bearing work.
##
## INPUT   lok_corpus_final.csv
## OUTPUT  out_sensitivity.csv
##
## Usage:  Rscript 04_sensitivity.R

source("lok_common.R")
source("02_lexical_diversity.R")       # main() does not run when sourced
source("03_pairwise_similarity.R")

BAND <- c(0.30, 0.70)


subset_corpus <- function(x, variant) {
  if (variant == "full") return(x)
  if (variant == "confident") {
    drop <- x$register_source == "model" &
      !is.na(x$p_narration) &
      x$p_narration >= BAND[1] & x$p_narration <= BAND[2]
    return(x[!drop, , drop = FALSE])
  }
  if (variant == "strict") {
    return(x[x$register_source %in% NON_MODEL_SOURCES, , drop = FALSE])
  }
  stop("unknown variant: ", variant)
}


## MTLD at a common token budget, per group, for one corpus variant.
diversity_for <- function(x) {
  groups <- bind_rows(
    protagonist_cells(x) %>% mutate(group = .data$cell),
    supporting_cast(x)   %>% mutate(group = "Supporting / dialogue")
  )
  gs <- split(groups, groups$group)
  lex <- sort(unique(unlist(lapply(gs, group_tokens), use.names = FALSE)))
  tok_lists <- lapply(gs, block_token_list)
  totals <- vapply(tok_lists, function(tl) sum(lengths(tl)), numeric(1))
  budget <- floor(min(totals) / 100) * 100
  out <- lapply(names(gs), function(g) {
    sub <- subsample_measures(tok_lists[[g]], budget, lex, R = 200)
    tibble::tibble(group = g,
                   tokens = totals[[g]],
                   budget = budget,
                   mtld_std = mean(sub[, "mtld"], na.rm = TRUE),
                   ttr_std = mean(sub[, "ttr"], na.rm = TRUE))
  })
  bind_rows(out)
}


## The register-versus-character contrast from script 03, without the
## permutation test, which is too slow to repeat for every variant.
similarity_for <- function(x) {
  docs <- build_documents(x)
  w <- tfidf_matrix(docs)
  s <- cosine_matrix(w)
  need <- c("Kain / narration", "Kain / dialogue",
            "Raziel / narration", "Raziel / dialogue")
  if (!all(need %in% rownames(s))) {
    return(tibble::tibble(cross_character = NA_real_,
                          cross_register = NA_real_,
                          difference = NA_real_))
  }
  cc <- mean(c(s["Kain / narration", "Raziel / narration"],
               s["Kain / dialogue",  "Raziel / dialogue"]))
  cr <- mean(c(s["Kain / narration", "Kain / dialogue"],
               s["Raziel / narration", "Raziel / dialogue"]))
  tibble::tibble(cross_character = cc, cross_register = cr,
                 difference = cc - cr)
}


main <- function() {
  x <- load_corpus()
  variants <- c("full", "confident", "strict")

  cat("\n== corpus size under each variant ==\n")
  sizes <- bind_rows(lapply(variants, function(v) {
    d <- subset_corpus(x, v)
    tibble::tibble(variant = v, blocks = nrow(d), words = sum(d$n_words),
                   pct_words = 100 * sum(d$n_words) / sum(x$n_words))
  }))
  print(as.data.frame(sizes), digits = 4, row.names = FALSE)

  cat("\n== protagonist cell sizes in words ==\n")
  cells <- bind_rows(lapply(variants, function(v) {
    protagonist_cells(subset_corpus(x, v)) %>%
      group_by(.data$cell) %>%
      summarise(words = sum(.data$n_words), .groups = "drop") %>%
      mutate(variant = v)
  })) %>% pivot_wider(names_from = "variant", values_from = "words")
  print(as.data.frame(cells), row.names = FALSE)

  cat("\n== MTLD at a common token budget ==\n")
  div <- bind_rows(lapply(variants, function(v) {
    diversity_for(subset_corpus(x, v)) %>% mutate(variant = v)
  }))
  print(as.data.frame(
    div %>% select("group", "variant", "mtld_std") %>%
      pivot_wider(names_from = "variant", values_from = "mtld_std")),
    digits = 4, row.names = FALSE)

  cat("\nMTLD ordering under each variant\n")
  for (v in variants) {
    d <- div %>% filter(.data$variant == v) %>% arrange(dplyr::desc(.data$mtld_std))
    cat("  ", format(v, width = 10), ": ",
        paste(d$group, collapse = " > "), "\n", sep = "")
  }

  cat("\n== register versus character similarity ==\n")
  sim <- bind_rows(lapply(variants, function(v) {
    similarity_for(subset_corpus(x, v)) %>% mutate(variant = v)
  })) %>% select("variant", dplyr::everything())
  print(as.data.frame(sim), digits = 3, row.names = FALSE)

  same_sign <- length(unique(sign(sim$difference[!is.na(sim$difference)]))) == 1
  cat("\nsign of the difference is stable across variants: ", same_sign, "\n",
      sep = "")

  res <- list(sizes = sizes, cells = cells, diversity = div, similarity = sim)
  readr::write_csv(div %>% left_join(sim, by = "variant"), "out_sensitivity.csv")
  cat("wrote out_sensitivity.csv\n")
  invisible(res)
}

if (sys.nframe() == 0) main()
