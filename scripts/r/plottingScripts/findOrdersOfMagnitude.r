# Rscript to find shape parameters for Gamma and Lognormal distributions
# as a function of order of magnitude span
# Authors: Basanta Khakurel

# Function to find Gamma shape parameter for a given order of magnitude
find_gamma_shape_for_order <- function(order_of_magnitude) {
  objective <- function(shape) {
    rate <- shape
    q025 <- qgamma(0.025, shape = shape, rate = rate)
    q975 <- qgamma(0.975, shape = shape, rate = rate)
    ratio <- q975 / q025
    target_ratio <- 10^order_of_magnitude
    return((ratio - target_ratio)^2)
  }
  result <- optimize(objective, interval = c(0.01, 100))
  return(result$minimum)
}

# Function to find Lognormal sigma parameter for a given order of magnitude
find_lognormal_sigma_for_order <- function(order_of_magnitude) {
  objective <- function(sigma) {
    mu <- -0.5 * sigma^2
    q025 <- qlnorm(0.025, meanlog = mu, sdlog = sigma)
    q975 <- qlnorm(0.975, meanlog = mu, sdlog = sigma)
    ratio <- q975 / q025
    target_ratio <- 10^order_of_magnitude
    return((ratio - target_ratio)^2)
  }
  result <- optimize(objective, interval = c(0.01, 10))
  return(result$minimum)
}

orders_of_magnitude <- 1:10

cat("Calculating optimal parameters for each order of magnitude...\n")

gamma_shapes <- sapply(orders_of_magnitude, find_gamma_shape_for_order)
lognormal_sigmas <- sapply(orders_of_magnitude, find_lognormal_sigma_for_order)

# Print in console
cat("\nResults:\n")
cat(paste(rep("=", 60), collapse = ""), "\n")
for (i in seq_along(orders_of_magnitude)) {
  cat(sprintf(
    "Orders of Magnitude: %2d | Gamma Shape: %7.4f | Lognormal Sigma: %7.4f\n",
    orders_of_magnitude[i], gamma_shapes[i], lognormal_sigmas[i]
  ))
}
cat(paste(rep("=", 60), collapse = ""), "\n")

# Create plot (comment this if plot is not wanted)
cairo_pdf("plots/OrderOfMagnitudeParameters.pdf", width = 10, height = 5, family = "Fira Sans")
par(mfrow = c(1, 2), mar = c(5, 5, 4, 2))

# Plot Gamma
plot(orders_of_magnitude, gamma_shapes,
  type = "b", pch = 19, col = "blue", lwd = 2,
  xlab = "Orders of Magnitude", ylab = expression("Shape Parameter (" * alpha * ")"),
  main = "Gamma Distribution",
  cex.main = 1.5, cex.lab = 1.2, cex.axis = 1.1
)
grid(col = "gray", lty = "dotted")

# Plot Lognormal
plot(orders_of_magnitude, lognormal_sigmas,
  type = "b", pch = 19, col = "red", lwd = 2,
  xlab = "Orders of Magnitude", ylab = expression("Shape Parameter (" * sigma * ")"),
  main = "Lognormal Distribution",
  cex.main = 1.5, cex.lab = 1.2, cex.axis = 1.1
)
grid(col = "gray", lty = "dotted")

dev.off()
# Reset plot parameters
par(mfrow = c(1, 1))

cat("\nPlot created successfully!\n")
