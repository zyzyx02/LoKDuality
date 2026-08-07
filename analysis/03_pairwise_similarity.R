## 03_pairwise_similarity.R
## Where does the Kain-Raziel pair sit among all character pairs?
##
## The critical reading the paper engages with holds that Kain and Raziel are
## two sides of the same coin. A cosine similarity between the two of them is
## not evidence for or against that on its own: any two characters in the same
## gothic script will share a great deal of vocabulary. The number only means
## something against the distribution of every other pair in the cast.
##
## The design also lets one further question be asked, which is the one the
## corpus is unusually well suited to. Each protagonist appears in two
## registers. So the same-register cross-character similarity can be compared
## against the same-character cross-register similarity. If two characters
## resemble each other more when they are doing the same narrative job than
## either resembles himself across jobs, the resemblance sits in the register
## rather than in the character.
##
## Documents are character-register units for the protagonists and one unit
## per supporting character. Weighting is tf-idf with L2 normalisation, so a
## long document is not favoured over a short one.
##
## INPUT   lok_corpus_final.csv
## OUTPUT  out_similarity_matrix.csv
##         out_similarity_pairs.csv
##
## Usage:  Rscript 03_pairwise_similarity.R

source("lok_common.R")

MIN_DOC_WORDS <- 300
N_PERM <- as.integer(Sys.getenv("LOK_NPERM", "500"))


build_documents <- function(x) {
  prot <- protagonist_cells(x) %>%
    mutate(doc = paste(.data$who, .data$register, sep = " / "),
           kind = "protagonist")
  sup <- supporting_cast(x, min_words = MIN_DOC_WORDS) %>%
    mutate(doc = .data$speaker_canon, kind = "supporting")
  bind_rows(prot, sup)
}


## Document-term matrix, then tf-idf, then L2 row normalisation.
tfidf_matrix <- function(docs) {
  tok <- docs %>%
    mutate(.w = strsplit(tolower(.data$text), "[^a-z']+")) %>%
    tidyr::unnest(".w") %>%
    rename(word = ".w") %>%
    filter(nzchar(.data$word), !grepl("^'+$", .data$word))

  counts <- tok %>% count(.data$doc, .data$word, name = "tf")
  dtm <- counts %>%
    pivot_wider(names_from = "word", values_from = "tf", values_fill = 0)
  rn <- dtm$doc
  m <- as.matrix(dtm[, -1, drop = FALSE])
  rownames(m) <- rn

  n_docs <- nrow(m)
  df <- colSums(m > 0)
  idf <- log(n_docs / df)
  w <- sweep(m, 2, idf, "*")
  norms <- sqrt(rowSums(w^2))
  norms[norms == 0] <- 1
  w / norms
}


cosine_matrix <- function(w) {
  s <- w %*% t(w)
  diag(s) <- NA_real_
  s
}


main <- function() {
  x <- load_corpus()
  docs <- build_documents(x)

  sizes <- docs %>%
    group_by(.data$doc, .data$kind) %>%
    summarise(blocks = dplyr::n(), words = sum(.data$n_words), .groups = "drop") %>%
    arrange(dplyr::desc(.data$words))
  cat("\n== documents ==\n")
  print(as.data.frame(sizes), row.names = FALSE)

  w <- tfidf_matrix(docs)
  s <- cosine_matrix(w)

  cat("\n== cosine similarity matrix ==\n")
  print(round(s, 3))

  ## Every unordered pair, as a pool to place specific pairs against.
  idx <- which(upper.tri(s), arr.ind = TRUE)
  pool <- tibble::tibble(
    a = rownames(s)[idx[, 1]],
    b = colnames(s)[idx[, 2]],
    cos = s[upper.tri(s)]
  ) %>% arrange(dplyr::desc(.data$cos))

  cat("\n== all pairs, most to least similar ==\n")
  print(as.data.frame(pool), digits = 3, row.names = FALSE)

  focus <- function(a, b) {
    v <- s[a, b]
    tibble::tibble(pair = paste(a, "vs", b), cos = v,
                   percentile = percentile_of(v, pool$cos),
                   rank = which(pool$a == a & pool$b == b |
                                  pool$a == b & pool$b == a)[1],
                   n_pairs = nrow(pool))
  }

  key <- bind_rows(
    focus("Kain / narration", "Raziel / narration"),
    focus("Kain / dialogue",  "Raziel / dialogue"),
    focus("Kain / narration", "Kain / dialogue"),
    focus("Raziel / narration", "Raziel / dialogue")
  )
  cat("\n== the four pairs the design was built for ==\n")
  print(as.data.frame(key), digits = 3, row.names = FALSE)

  cross_char <- mean(c(s["Kain / narration", "Raziel / narration"],
                       s["Kain / dialogue",  "Raziel / dialogue"]))
  cross_reg <- mean(c(s["Kain / narration", "Kain / dialogue"],
                      s["Raziel / narration", "Raziel / dialogue"]))
  cat("\nmean same-register, different character : ",
      sprintf("%.3f", cross_char), "\n", sep = "")
  cat("mean same-character, different register: ",
      sprintf("%.3f", cross_reg), "\n", sep = "")
  cat("difference (register minus character)  : ",
      sprintf("%+.3f", cross_char - cross_reg), "\n", sep = "")

  ## Permutation test on that difference. Character labels are shuffled inside
  ## each register, so register composition is held fixed and only the
  ## character assignment moves. A large observed difference relative to the
  ## permuted ones means the register is doing the work.
  prot <- docs %>% filter(.data$kind == "protagonist")
  sup <- docs %>% filter(.data$kind == "supporting")
  observed <- cross_char - cross_reg

  set.seed(20260804)
  perm <- numeric(N_PERM)
  for (i in seq_len(N_PERM)) {
    p <- prot
    p$who_perm <- unsplit(lapply(split(p$who, p$register), sample),
                          p$register)
    p$doc <- paste(p$who_perm, p$register, sep = " / ")
    ww <- tfidf_matrix(bind_rows(p, sup))
    ss <- cosine_matrix(ww)
    cc <- mean(c(ss["Kain / narration", "Raziel / narration"],
                 ss["Kain / dialogue",  "Raziel / dialogue"]))
    cr <- mean(c(ss["Kain / narration", "Kain / dialogue"],
                 ss["Raziel / narration", "Raziel / dialogue"]))
    perm[i] <- cc - cr
  }
  p_hi <- (1 + sum(perm >= observed)) / (N_PERM + 1)
  p_lo <- (1 + sum(perm <= observed)) / (N_PERM + 1)
  p_val <- min(1, 2 * min(p_hi, p_lo))
  cat("\npermutation test, character labels shuffled within register\n")
  cat("  The null here is that the character labels carry no information.\n")
  cat("  Under that null the two same-register documents are random halves\n")
  cat("  of one pool, so they resemble each other strongly and the\n")
  cat("  difference is large. An observed value well BELOW the permuted\n")
  cat("  distribution therefore means the character labels do carry signal.\n")
  cat("  Read the two-sided p, not the upper tail alone.\n")
  cat("  observed difference : ", sprintf("%+.3f", observed), "\n", sep = "")
  cat("  permuted mean       : ", sprintf("%+.3f", mean(perm)), "\n", sep = "")
  cat("  permuted 2.5-97.5%  : ",
      sprintf("[%+.3f, %+.3f]",
              stats::quantile(perm, 0.025), stats::quantile(perm, 0.975)),
      "\n", sep = "")
  cat("  two-sided p         : ", sprintf("%.4f", p_val), "\n", sep = "")
  cat("  direction           : observed is ",
      if (observed < mean(perm)) "BELOW" else "ABOVE",
      " the permuted mean\n", sep = "")

  readr::write_csv(as.data.frame(round(s, 6)) %>%
                     tibble::rownames_to_column("doc"),
                   "out_similarity_matrix.csv")
  readr::write_csv(pool, "out_similarity_pairs.csv")
  cat("\nwrote out_similarity_matrix.csv, out_similarity_pairs.csv\n")
}

if (sys.nframe() == 0) main()
