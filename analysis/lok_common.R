## lok_common.R
## Shared loading, cell definitions and helpers for the Legacy of Kain
## register analysis. Sourced by every numbered script.
##
## The corpus is lok_corpus_final.csv, produced by the Python pipeline.
## Every speech block carries a register label (narration or dialogue) and a
## register_source recording where that label came from, which matters for the
## sensitivity analysis in 04.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
})

CORPUS_PATH <- Sys.getenv("LOK_CORPUS", "lok_corpus_final.csv")

PROTAGONISTS <- c("Kain", "Raziel")

## Label sources that did not come from the classifier. "none" is the label
## used for a block that carries no marker in a game whose transcript does mark
## narration; the absence of a marker is itself source evidence, so it belongs
## here. Leaving it out silently discards 383 blocks of source-attested
## dialogue and produces a different strict variant.
NON_MODEL_SOURCES <- c("explicit_paren", "explicit_vo", "none",
                       "constraint", "manual")

## Blocks the classifier was least sure about. The band matches the one used
## when the review queue was generated.
UNCERTAIN_BAND <- c(0.35, 0.65)

GAME_ORDER <- c("Blood Omen", "Soul Reaver", "Soul Reaver 2",
                "Blood Omen 2", "Defiance")


load_corpus <- function(path = CORPUS_PATH) {
  if (!file.exists(path)) {
    stop("corpus not found: ", path,
         "\nSet LOK_CORPUS or run the script from the folder holding it.")
  }
  x <- read_csv(path, show_col_types = FALSE, progress = FALSE)

  needed <- c("game", "scene_id", "seq", "speaker_canon", "type",
              "register", "register_source", "p_narration", "text")
  missing <- setdiff(needed, names(x))
  if (length(missing)) stop("corpus is missing column(s): ",
                            paste(missing, collapse = ", "))

  x <- x %>%
    filter(.data$type == "speech") %>%
    mutate(
      game = factor(.data$game, levels = GAME_ORDER),
      register = factor(.data$register, levels = c("narration", "dialogue")),
      p_narration = suppressWarnings(as.numeric(.data$p_narration)),
      block_id = paste(.data$game, .data$seq, sep = "|"),
      n_words = str_count(.data$text, "\\S+")
    )

  stray <- sum(is.na(x$register))
  if (stray > 0) {
    stop(stray, " speech blocks have no register label. ",
         "Finish the merge step before running the analysis.")
  }
  x
}


## Kain and Raziel only, with the game-by-register cell as a factor.
protagonist_cells <- function(x) {
  x %>%
    filter(.data$speaker_canon %in% PROTAGONISTS) %>%
    mutate(
      who = factor(.data$speaker_canon, levels = PROTAGONISTS),
      cell = paste(.data$who, .data$register, sep = " / ")
    )
}


## Everyone who is not Kain or Raziel. All of it is dialogue by the narrator
## constraint, so this is the register baseline for the gothic vocabulary of
## the series rather than a second comparison group.
supporting_cast <- function(x, min_words = 300) {
  x %>%
    filter(!.data$speaker_canon %in% PROTAGONISTS,
           .data$speaker_canon != "") %>%
    group_by(.data$speaker_canon) %>%
    filter(sum(.data$n_words) >= min_words) %>%
    ungroup()
}


## Word tokens, lower-cased, apostrophes kept so contractions survive.
tokenise <- function(x, text_col = "text") {
  x %>%
    mutate(.tok = str_split(str_to_lower(.data[[text_col]]),
                            "[^a-z']+")) %>%
    tidyr::unnest(".tok") %>%
    filter(.data$.tok != "", !str_detect(.data$.tok, "^'+$")) %>%
    rename(word = ".tok")
}


## Percentile of a value inside a numeric vector, reported as a proportion.
## Used to place the Kain-Raziel pair inside the distribution of all pairs.
percentile_of <- function(value, pool) {
  mean(pool <= value, na.rm = TRUE)
}


## Bootstrap by resampling whole speech blocks. Words inside one block are not
## independent, so resampling tokens would understate the uncertainty.
block_bootstrap <- function(df, stat_fun, R = 2000, seed = 20260804) {
  set.seed(seed)
  blocks <- unique(df$block_id)
  n <- length(blocks)
  out <- numeric(R)
  for (i in seq_len(R)) {
    pick <- sample(blocks, n, replace = TRUE)
    idx <- unlist(lapply(pick, function(b) which(df$block_id == b)),
                  use.names = FALSE)
    resampled <- df[idx, , drop = FALSE]
    out[i] <- stat_fun(resampled)
  }
  out
}


fmt_ci <- function(v, digits = 3) {
  q <- stats::quantile(v, c(0.025, 0.975), na.rm = TRUE)
  sprintf("[%.*f, %.*f]", digits, q[[1]], digits, q[[2]])
}
