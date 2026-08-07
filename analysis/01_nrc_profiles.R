## 01_nrc_profiles.R
## NRC emotion profiles for the four protagonist cells (Kain and Raziel, each
## in narration and in dialogue) with the supporting cast as a register
## baseline.
##
## Why the baseline is needed. The series is written in a uniformly gothic
## register: blood, dark, death and abyss carry negative NRC weight whoever
## says them. Without a comparison group there is no way to separate a
## character effect from the house style of the writing. The supporting cast
## is entirely dialogue by the narrator constraint, so it fixes the vocabulary
## baseline without confounding the register contrast.
##
## Scoring runs once per speech block via syuzhet::get_nrc_sentiment, the same
## function used in the earlier work on this corpus. Block-level counts are
## then aggregated, which keeps the bootstrap cheap: resampling works on a
## count matrix rather than on the token table.
##
## Two normalisations are reported, because they answer different questions.
##   share    each emotion as a proportion of the eight emotion counts.
##            Comparable across groups that differ in emotional density.
##   rate100  emotion hits per 100 words. Sensitive to that density, which
##            itself differs between narration and dialogue.
##
## syuzhet also returns positive and negative. Those are valence categories,
## not members of the eight-emotion set, and are left out of the denominator
## so that no token is counted twice.
##
## INPUT   lok_corpus_final.csv
## OUTPUT  out_nrc_block_scores.csv   (cache, safe to delete)
##         out_nrc_profiles.csv
##         out_nrc_contrasts.csv
##
## Usage:  Rscript 01_nrc_profiles.R

source("lok_common.R")

if (nzchar(Sys.getenv("LOK_STUB_SYUZHET"))) {
  source(Sys.getenv("LOK_STUB_SYUZHET"))
} else {
  suppressPackageStartupMessages(library(syuzhet))
}

EMOTIONS <- c("anger", "anticipation", "disgust", "fear",
              "joy", "sadness", "surprise", "trust")

CACHE <- "out_nrc_block_scores.csv"
R_BOOT <- 2000


## The cache is keyed on the text itself, not only on the block identifiers.
## An earlier version compared identifiers alone, which silently reused stale
## scores after the text of a block had been edited while its id stayed the
## same. Any edit to the corpus now forces a rescore.
corpus_fingerprint <- function(x) {
  txt <- paste(x$block_id, x$text, collapse = "\r")
  bytes <- as.integer(charToRaw(txt))
  paste(nrow(x),
        sum(x$n_words),
        nchar(txt),
        format(sum(bytes), scientific = FALSE),
        format(sum(bytes * (seq_along(bytes) %% 251 + 1)) %% 1000000007,
               scientific = FALSE),
        sep = "-")
}


score_blocks <- function(x, cache = CACHE) {
  fp <- corpus_fingerprint(x)
  fp_file <- paste0(cache, ".fingerprint")
  if (file.exists(cache) && file.exists(fp_file)) {
    if (identical(readLines(fp_file, warn = FALSE)[1], fp)) {
      message("using cached NRC scores in ", cache)
      return(readr::read_csv(cache, show_col_types = FALSE, progress = FALSE))
    }
    message("corpus has changed since the cache was written, rescoring")
  } else if (file.exists(cache)) {
    message("cache has no fingerprint, rescoring")
  }
  message("scoring ", nrow(x), " blocks with syuzhet::get_nrc_sentiment")
  nrc <- get_nrc_sentiment(x$text)
  out <- dplyr::bind_cols(
    x[, c("block_id", "game", "speaker_canon", "register",
          "register_source", "p_narration", "n_words")],
    nrc[, EMOTIONS]
  )
  readr::write_csv(out, cache)
  writeLines(fp, fp_file)
  out
}


group_profile <- function(d) {
  counts <- colSums(d[, EMOTIONS, drop = FALSE])
  total <- sum(counts)
  words <- sum(d$n_words)
  tibble::tibble(
    emotion = EMOTIONS,
    n = as.integer(counts),
    share = if (total > 0) as.numeric(counts / total) else NA_real_,
    rate100 = if (words > 0) as.numeric(100 * counts / words) else NA_real_
  )
}


## Block bootstrap on the count matrix. Words inside one utterance are not
## independent of one another, so the resampling unit is the whole block.
boot_diff <- function(da, db, measure, R = R_BOOT, seed = 20260804) {
  set.seed(seed)
  na <- nrow(da); nb <- nrow(db)
  out <- matrix(NA_real_, nrow = R, ncol = length(EMOTIONS),
                dimnames = list(NULL, EMOTIONS))
  for (i in seq_len(R)) {
    sa <- group_profile(da[sample.int(na, na, replace = TRUE), , drop = FALSE])
    sb <- group_profile(db[sample.int(nb, nb, replace = TRUE), , drop = FALSE])
    out[i, ] <- sa[[measure]] - sb[[measure]]
  }
  out
}


contrast_table <- function(scored, group_a, group_b, measure = "share") {
  da <- scored[scored$group == group_a, , drop = FALSE]
  db <- scored[scored$group == group_b, , drop = FALSE]
  if (nrow(da) == 0 || nrow(db) == 0) {
    stop("empty group in contrast: ", group_a, " vs ", group_b)
  }
  point <- group_profile(da)[[measure]] - group_profile(db)[[measure]]
  boot <- boot_diff(da, db, measure)
  lo <- apply(boot, 2, stats::quantile, probs = 0.025, na.rm = TRUE)
  hi <- apply(boot, 2, stats::quantile, probs = 0.975, na.rm = TRUE)
  tibble::tibble(
    a = group_a, b = group_b, measure = measure, emotion = EMOTIONS,
    diff = point, lo = as.numeric(lo), hi = as.numeric(hi),
    excludes_zero = (as.numeric(lo) > 0 | as.numeric(hi) < 0)
  )
}


assign_groups <- function(x) {
  prot <- protagonist_cells(x) %>% mutate(group = .data$cell)
  sup <- supporting_cast(x) %>% mutate(group = "Supporting / dialogue")
  bind_rows(prot, sup)
}


main <- function() {
  x <- load_corpus()
  groups <- assign_groups(x)
  scored <- score_blocks(groups)
  scored$group <- groups$group[match(scored$block_id, groups$block_id)]
  scored <- scored[!is.na(scored$group), , drop = FALSE]

  profiles <- scored %>%
    group_by(.data$group) %>%
    group_modify(~ group_profile(.x)) %>%
    ungroup()

  cat("\n== NRC profile: share of the eight emotion counts ==\n")
  print(as.data.frame(
    profiles %>% select("group", "emotion", "share") %>%
      pivot_wider(names_from = "emotion", values_from = "share")),
    digits = 3, row.names = FALSE)

  cat("\n== NRC profile: emotion hits per 100 words ==\n")
  print(as.data.frame(
    profiles %>% select("group", "emotion", "rate100") %>%
      pivot_wider(names_from = "emotion", values_from = "rate100")),
    digits = 3, row.names = FALSE)

  sizes <- scored %>%
    group_by(.data$group) %>%
    summarise(blocks = dplyr::n(),
              words = sum(.data$n_words),
              emotion_hits = sum(as.matrix(dplyr::pick(dplyr::all_of(EMOTIONS)))),
              .groups = "drop")
  cat("\n== group sizes ==\n")
  print(as.data.frame(sizes), row.names = FALSE)

  ## First two pairs: register effect inside each character.
  ## Next two: character effect inside each register.
  ## Last two: each protagonist against the supporting-cast baseline.
  pairs <- list(
    c("Kain / narration",   "Kain / dialogue"),
    c("Raziel / narration", "Raziel / dialogue"),
    c("Kain / narration",   "Raziel / narration"),
    c("Kain / dialogue",    "Raziel / dialogue"),
    c("Kain / dialogue",    "Supporting / dialogue"),
    c("Raziel / dialogue",  "Supporting / dialogue")
  )

  res <- bind_rows(lapply(pairs, function(p)
    bind_rows(contrast_table(scored, p[1], p[2], "share"),
              contrast_table(scored, p[1], p[2], "rate100"))))

  cat("\n== contrasts on 'share', 95% block-bootstrap intervals ==\n")
  cat("   excludes_zero TRUE means the interval does not cover 0\n")
  print(as.data.frame(res %>% filter(.data$measure == "share")),
        digits = 3, row.names = FALSE)

  readr::write_csv(profiles, "out_nrc_profiles.csv")
  readr::write_csv(res, "out_nrc_contrasts.csv")
  cat("\nwrote out_nrc_profiles.csv, out_nrc_contrasts.csv, ", CACHE, "\n", sep = "")
}

if (sys.nframe() == 0) main()
