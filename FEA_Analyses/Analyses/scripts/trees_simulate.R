#!/usr/bin/env Rscript

library(ape)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)

if (length(file_arg) > 0) {
  script_file <- normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)
  analysis_dir <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
} else {
  cwd <- normalizePath(getwd(), mustWork = TRUE)
  analysis_dir <- if (basename(cwd) == "scripts") {
    dirname(cwd)
  } else if (file.exists(file.path(cwd, "Analyses", "simulation_metadata.csv")) || dir.exists(file.path(cwd, "Analyses"))) {
    file.path(cwd, "Analyses")
  } else {
    cwd
  }
}

set.seed(33)
tree_dir <- file.path(analysis_dir, "trees")
metadata_file <- file.path(analysis_dir, "simulation_metadata.csv")

force_trees <- tolower(Sys.getenv("FORCE_TREES", "0")) %in% c("1", "true", "yes", "y")
existing_tree_files <- if (dir.exists(tree_dir)) {
  list.files(tree_dir, pattern = "^tree_[0-9]+\\.nwk$", full.names = TRUE)
} else {
  character()
}

if (!force_trees && (length(existing_tree_files) > 0 || file.exists(metadata_file))) {
  stop(
    paste(
      "Existing trees or simulation metadata found.",
      "Refusing to overwrite them.",
      "Set FORCE_TREES=1 only if you intentionally want to regenerate the shared trees."
    )
  )
}

dir.create(tree_dir, showWarnings = FALSE)

sim_meta <- data.frame(id = 1:1000, true_mean_bl = numeric(1000))

for (i in 1:1000) {
  tree <- rtree(n = 250)

  r <- runif(1, min = -5, max = -2)
  target_mean <- 10^r

  current_mean <- mean(tree$edge.length)
  scale_factor <- target_mean / current_mean
  tree$edge.length <- tree$edge.length * scale_factor

  write.tree(tree, file = file.path(tree_dir, paste0("tree_", i, ".nwk")))
  sim_meta$true_mean_bl[i] <- target_mean
}

write.csv(sim_meta, metadata_file, row.names = FALSE)
message("Generated 1000 trees in ", tree_dir)
