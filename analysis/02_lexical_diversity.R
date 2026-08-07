## 02_lexical_diversity.R
## Lexical diversity for the four protagonist cells and the supporting cast.
##
## The earlier analysis of this corpus used the type-token ratio. TTR falls as
## a text gets longer, so a group with more words is pushed towards a lower
## value whatever its actual vocabulary. Kain and Raziel differ in total
## length, and narration blocks are longer than dialogue blocks, so both
## contrasts of interest are confounded with the measure itself.
##
## Two corrections are applied here.
##
## First, MTLD (McCarthy and Jarvis 2010) is reported alongside TTR. It counts
## how many sequential factors of text are needed before the running TTR falls
## to a threshold, and does not decline with length the way TTR does. Forward
## and backward passes are averaged, as in the original definition.
##
## Second, both measures are also computed at a common token budget. Every
## group is reduced to the same number of tokens by sampling whole blocks
## without replacement, repeatedly. This makes the groups directly comparable
## and gives a spread that reflects which blocks happened to be included.
##
## A note on why the resampling is done without replacement. An ordinary
## bootstrap draws blocks with replacement, so the same block can appear
## several times in one replicate. Repeated text lowers any diversity measure
## mechanically, which pushes the whole interval below the point estimate.
## Subsampling avoids that, at the cost of describing variability under
## subsampling rather than a textbook bootstrap interval.
##
## INPUT   lok_corpus_final.csv
## OUTPUT  out_lexical_diversity.csv
##
## Usage:  Rscript 02_lexical_diversity.R

source("lok_common.R")

TTR_THRESHOLD <- 0.72
R_SUB <- 300          # subsampling replicates
MIN_TOKENS <- 100     # MTLD is unstable below roughly this many tokens


## One directional MTLD pass. Tokens are pre-coded as integers by the caller
## so that type lookup is a constant-time flag check rather than a scan.
mtld_pass <- function(codes, n_types_total, threshold = TTR_THRESHOLD) {
  n <- length(codes)
  if (n == 0) return(NA_real_)
  seen <- logical(n_types_total)
  factors <- 0
  n_types <- 0L
  count <- 0L
  ttr <- 1
  for (i in seq_len(n)) {
    count <- count + 1L
    k <- codes[i]
    if (!seen[k]) {
      seen[k] <- TRUE
      n_types <- n_types + 1L
    }
    ttr <- n_types / count
    if (ttr <= threshold) {
      factors <- factors + 1
      seen[] <- FALSE
      n_types <- 0L
      count <- 0L
      ttr <- 1
    }
  }
  if (count > 0) factors <- factors + (1 - ttr) / (1 - threshold)
  if (factors <= 0) return(NA_real_)
  n / factors
}


mtld <- function(codes, n_types_total, threshold = TTR_THRESHOLD) {
  if (length(codes) < MIN_TOKENS) return(NA_real_)
  mean(c(mtld_pass(codes, n_types_total, threshold),
         mtld_pass(rev(codes), n_types_total, threshold)))
}


ttr_of <- function(codes) {
  if (!length(codes)) return(NA_real_)
  length(unique(codes)) / length(codes)
}


## Tokens for one group, kept in text order so MTLD sees a real sequence.
group_tokens <- function(d) {
  d <- d[order(d$game, d$seq), , drop = FALSE]
  tok <- unlist(strsplit(tolower(d$text), "[^a-z']+"), use.names = FALSE)
  tok[nzchar(tok) & !grepl("^'+$", tok)]
}


## Token vector per block, in order, so a subsample can be assembled quickly.
block_token_list <- function(d) {
  d <- d[order(d$game, d$seq), , drop = FALSE]
  lapply(strsplit(tolower(d$text), "[^a-z']+"),
         function(v) v[nzchar(v) & !grepl("^'+$", v)])
}


## Draw whole blocks without replacement until the token budget is reached.
subsample_measures <- function(tok_list, budget, lex, R = R_SUB,
                               seed = 20260804) {
  set.seed(seed)
  lens <- lengths(tok_list)
  nb <- length(tok_list)
  out <- matrix(NA_real_, nrow = R, ncol = 2,
                dimnames = list(NULL, c("mtld", "ttr")))
  for (i in seq_len(R)) {
    ord <- sample.int(nb)
    cum <- cumsum(lens[ord])
    k <- which(cum >= budget)[1]
    if (is.na(k)) k <- nb
    tok <- unlist(tok_list[sort(ord[seq_len(k)])], use.names = FALSE)
    if (length(tok) > budget) tok <- tok[seq_len(budget)]
    codes <- match(tok, lex)
    out[i, ] <- c(mtld(codes, length(lex)), ttr_of(codes))
  }
  out
}


main <- function() {
  x <- load_corpus()
  groups <- bind_rows(
    protagonist_cells(x) %>% mutate(group = .data$cell),
    supporting_cast(x)   %>% mutate(group = "Supporting / dialogue")
  )
  gs <- split(groups, groups$group)

  ## A single vocabulary shared by every group, so integer codes are stable.
  lex <- sort(unique(unlist(lapply(gs, group_tokens), use.names = FALSE)))

  tok_lists <- lapply(gs, block_token_list)
  totals <- vapply(tok_lists, function(tl) sum(lengths(tl)), numeric(1))
  budget <- floor(min(totals) / 100) * 100
  cat("common token budget: ", budget,
      " (smallest group has ", min(totals), " tokens)\n", sep = "")

  rows <- lapply(names(gs), function(g) {
    tk <- group_tokens(gs[[g]])
    codes <- match(tk, lex)
    sub <- subsample_measures(tok_lists[[g]], budget, lex)
    tibble::tibble(
      group = g,
      blocks = nrow(gs[[g]]),
      tokens = length(tk),
      types = length(unique(tk)),
      ttr_full = ttr_of(codes),
      mtld_full = mtld(codes, length(lex)),
      ttr_std = mean(sub[, "ttr"], na.rm = TRUE),
      ttr_std_lo = unname(stats::quantile(sub[, "ttr"], 0.025, na.rm = TRUE)),
      ttr_std_hi = unname(stats::quantile(sub[, "ttr"], 0.975, na.rm = TRUE)),
      mtld_std = mean(sub[, "mtld"], na.rm = TRUE),
      mtld_std_lo = unname(stats::quantile(sub[, "mtld"], 0.025, na.rm = TRUE)),
      mtld_std_hi = unname(stats::quantile(sub[, "mtld"], 0.975, na.rm = TRUE))
    )
  })
  res <- bind_rows(rows)

  cat("\n== on the full text of each group ==\n")
  print(as.data.frame(res[, c("group", "blocks", "tokens", "types",
                              "ttr_full", "mtld_full")]),
        digits = 4, row.names = FALSE)

  cat("\n== at a common token budget, mean and 2.5-97.5 percentiles ==\n")
  print(as.data.frame(res[, c("group", "ttr_std", "ttr_std_lo", "ttr_std_hi",
                              "mtld_std", "mtld_std_lo", "mtld_std_hi")]),
        digits = 4, row.names = FALSE)

  ## If the full-text TTR ordering tracks token count and the standardised
  ## ordering does not, the original ordering was a length artefact.
  cat("\n== ordering ==\n")
  cat("by token count    : ",
      paste(res$group[order(-res$tokens)], collapse = " > "), "\n")
  cat("by TTR, full text : ",
      paste(res$group[order(-res$ttr_full)], collapse = " > "), "\n")
  cat("by TTR, budgeted  : ",
      paste(res$group[order(-res$ttr_std)], collapse = " > "), "\n")
  cat("by MTLD, budgeted : ",
      paste(res$group[order(-res$mtld_std)], collapse = " > "), "\n")
  cat("\nSpearman rho with token count, TTR full text : ",
      sprintf("%.3f", stats::cor(res$ttr_full, res$tokens, method = "spearman")),
      "\nSpearman rho with token count, MTLD budgeted  : ",
      sprintf("%.3f", stats::cor(res$mtld_std, res$tokens, method = "spearman")),
      "\n", sep = "")

  readr::write_csv(res, "out_lexical_diversity.csv")
  cat("\nwrote out_lexical_diversity.csv\n")
}

if (sys.nframe() == 0) main()
