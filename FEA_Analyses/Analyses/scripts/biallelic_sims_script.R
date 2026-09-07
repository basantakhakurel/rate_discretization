# Calculation of maximum likelihood branch lengths for a star-like tree with a gamma rate distribution
# This script is not written by me (Basanta), it was obtained from the supplementary materials of Feretti et al. 2026.
library(tidyverse)
library(viridis)
library(pilot)

set_pilot_family(family = "Fira Sans")

# The real distribution of site rate heterogeneity

d_realdistr <- dgamma
q_realdistr <- qgamma


# Generate realistic values for counts of derived alleles by drawing rates for each site and calculating the number
# of 1s amongst the nsamples values at each tip

# nsamples is the number of tips
# nsites if the number of sites in the genome
# shape is the shape of the generating gamma distribution
# lambda is the branch length

k_vs_n_random <- function(nsamples, nsites, shape, lambda) {
  rbinom(
    n = nsites, size = nsamples,
    prob = 0.5 * (1 - exp(-2 * lambda *
      q_realdistr((c(1:nsites) - 0.5) / nsites, shape = shape, scale = 1 / shape)))
  )
}

# Get DGM rates for a given number of categories, shape and scale
# The mean value on each quantile:
discretised_mean <- function(ncat, shape, scale) {
  sapply(1:ncat, function(i) {
    integrate(
      function(y) {
        y * dgamma(y, shape = shape, scale = scale)
      },
      lower = qgamma((i - 1) / ncat, shape = shape, scale = scale),
      upper = qgamma(i / ncat, shape = shape, scale = scale)
    )$value * ncat
  })
}

# The median:
discretised_median <- function(ncat, shape, scale) {
  sapply(1:ncat, function(i) {
    qgamma((i - 0.5) / ncat, shape = shape, scale = scale)
  })
}

# DGM log-likelihood with fixed value for the gamma shape
# input is test value for the branch length
# shape is the dicsrete gamme shape parameter
# ncat if the number of categories
# k is vector of site-specific rate variations (mean of 1)
# nsamples is the number of tips in the tree

logL_fixshape <- function(input, shape, ncat, k, nsamples) {
  lambda <- exp(input[1])
  z <- discretised_mean(ncat = ncat, shape = 0.01 + exp(shape), scale = 1 / (0.01 + exp(shape)))
  tmp <- sum(log(sapply(k, function(kx) {
    sum(((1 - exp(-2 * lambda * z)))^kx * ((1 + exp(-2 * lambda * z)))^(nsamples - kx))
  }))) - length(k) * log(ncat) - nsamples * log(2)
  tmp
}

# The number of sites in the genome
nsites <- 5000

# The true shape of the gamma distribution
# real_shape<-0.65
# real_shape<-1.12
real_shape <- 3.36
# real_shape<-0.5

# branch lengths to test
branchlengths <- c(0.00005, 0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1)


# choices for number of DGM rate categories
ncategories <- 4

# choices for sample size
ssizes <- seq(50, 1000, by = 50)

# number of draws from the RR distribution (for credible interval)
nreps <- 10

# generate results
combos <- tibble(real_lambda = branchlengths) |> # one row per branch length
  mutate(ncat = list(c(ncategories))) |>
  unnest(ncat) |> # one row per number of categories
  mutate(nsamples = list(c(ssizes))) |>
  unnest(nsamples) |> # one row per sample size
  mutate(mls_knownshape = pmap(list(real_lambda, ncat, nsamples), function(rl, nc, ns) { # calculate likelihoods
    optimisations <- map(1:nreps, function(rep) { # 100 draws from the rate distribution
      k <- k_vs_n_random(ns, nsites, real_shape, rl) # draw from the distribution
      temp_par <- optimize(logL_fixshape, shape = log(real_shape), k = k, ncat = nc, nsamples = ns, interval = c(-100000000, 1000), maximum = TRUE)$maximum # numerical ML branch length
      list(log_lambda = temp_par[1], log_shape = log(real_shape))
    }) |> bind_rows()
    out <- colMeans(exp(optimisations))

    lower.ci <- quantile(exp(optimisations$log_lambda), 0.025)

    upper.ci <- quantile(exp(optimisations$log_lambda), 0.975)
    out <- c(out, lower.ci, upper.ci)
    names(out) <- c(names(out)[1:2], "log_lambda_5", "log_lambda_95")
    out
  }))

combos <- combos |>
  unnest_wider(mls_knownshape)

combos <- combos |>
  mutate(char_real_lambda = as.character(real_lambda)) |>
  mutate(char_real_lambda = factor(char_real_lambda)) |>
  mutate(char_real_lambda = fct_relevel(char_real_lambda, c("5e-05", "1e-04", "5e-04")))


# Plot (figure 4)

p <- ggplot(data = combos |> filter(nsamples <= 1050), aes(x = nsamples, y = log_lambda / real_lambda, group = real_lambda, col = char_real_lambda)) +
  facet_wrap(~char_real_lambda, nrow = 2) +
  geom_hline(yintercept = 1) +
  # ylim(c(0.5,1.9)) +
  geom_line() +
  geom_errorbar(aes(x = nsamples, ymin = log_lambda_5 / real_lambda, ymax = log_lambda_95 / real_lambda, col = char_real_lambda)) +
  scale_colour_viridis(name = "True\nbranch\nlength\n(subs/site)", discrete = TRUE, guide = "none") +
  ylab("Inferred branch length / true branch length") +
  xlab("Number of tips") +
  theme_pilot()

plot_name <- paste0("Ferreti_alpha_", real_shape, ".pdf")
ggsave(plot_name, p, width = 8, height = 6, device = cairo_pdf, limitsize = FALSE)
