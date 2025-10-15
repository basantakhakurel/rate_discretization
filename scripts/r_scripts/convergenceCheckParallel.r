# R script to test for convergence in simulations output
# Author: Basanta Khakurel
# Date: 2025-09-15

packages <- c("convenience", "stringr", "dplyr", "future", "future.apply")

for (package in packages) {
  tryCatch(
    {
      if (!require(package, character.only = TRUE)) {
        install.packages(package)
        library(package, character.only = TRUE)
      }
    },
    error = function(e) {
      message(paste0("Could not install ", package, ": ", e$message))
    }
  )
}


CONFIG <- list(
  BASE_DIR = "inference_results",
  SIM_ID_TO_CHECK = "sim_1",
  NUM_RUNS = 4,
  BURNIN_FRAC = 0.1
)

num_cores_to_use <- availableCores() - 1
plan(multisession, workers = num_cores_to_use)
cat("--- Parallel processing enabled, using", num_cores_to_use, "cores. ---\n")

check_convergence <- function(base_dir, sim_id = NULL) {
  cat("--- Starting Convergence Check ---\n")
  cat("Scanning for result directories in:", base_dir, "\n")

  all_dirs <- list.dirs(path = base_dir, recursive = TRUE)
  potential_dirs <- all_dirs[grepl("Gamma|Lognormal", all_dirs) & grepl("sim_", all_dirs)]

  if (!is.null(sim_id)) {
    cat("Filtering for directories matching ID:", sim_id, "\n")
    sim_pattern <- paste0("/", sim_id, "$")
    target_dirs <- potential_dirs[grepl(sim_pattern, potential_dirs)]
  } else {
    cat("No specific simulation provided. Processing all found simulations.\n")
    target_dirs <- potential_dirs
  }

  if (length(target_dirs) == 0) {
    user_message <- ifelse(!is.null(sim_id), paste("for ID:", sim_id), "")
    stop(paste("No result directories were found", user_message, ". Please check your configuration."))
  }

  cat("Found", length(target_dirs), "analysis directories to process.\n")
  cat("Distributing tasks across cores... (Nothing will be printed in real-time)\n\n")

  results_list <- future_lapply(target_dirs, function(dir_path) {
    sim_rep <- str_match(dir_path, "/sim_([0-9]+)")[1, 2]
    inf_model_match <- str_match(dir_path, "with_([^_/]+)")
    inf_model <- ifelse(!is.na(inf_model_match[1, 2]), inf_model_match[1, 2], NA)
    inf_k_match <- str_match(dir_path, "with_.*_k([0-9]+)")
    inf_k <- ifelse(!is.na(inf_k_match[1, 2]), inf_k_match[1, 2], NA)
    sim_string <- str_match(dir_path, "on_([^/]+)")[1, 2]
    sim_model <- str_remove(sim_string, "_[0-9]+$")
    sim_k <- str_extract(sim_string, "[0-9]+$")
    if (is.na(sim_k)) {
      sim_k <- "cont"
    }

    first_log <- list.files(path = dir_path, pattern = "_run_1\\.log$", full.names = FALSE)
    if (length(first_log) == 0) {
      return(NULL)
    }
    base_filename <- str_remove(first_log[1], "_run_1\\.log$")
    op_files <- c(
      file.path(dir_path, sprintf("%s_run_%d.log", base_filename, 1:CONFIG$NUM_RUNS)),
      file.path(dir_path, sprintf("%s_run_%d.trees", base_filename, 1:CONFIG$NUM_RUNS))
    )
    if (!all(sapply(op_files, file.exists))) {
      return(NULL)
    }

    status <- tryCatch(
      {
        convCheck <- convenience::checkConvergence(list_files = op_files, control = convenience::makeControl(burnin = CONFIG$BURNIN_FRAC))
        ifelse(convCheck$converged, "Converged", "Failed")
      },
      error = function(e) {
        return("Error")
      }
    )

    dplyr::tibble(
      sim_replicate = as.integer(sim_rep), sim_model = sim_model, sim_k = sim_k,
      inf_model = inf_model, inf_k = as.integer(inf_k), convergence_status = status,
      directory = dir_path
    )
  }, future.seed = TRUE)

  final_summary <- bind_rows(results_list)

  output_tag <- ifelse(is.null(sim_id), "all_sims", sim_id)
  output_filename <- paste0("convergence_summary_", output_tag, ".csv")

  if (nrow(final_summary) > 0) {
    write.csv(final_summary, file = output_filename, row.names = FALSE)
    cat("\n--- All checks complete. ---\n")
    cat("Summary of", nrow(final_summary), "analyses saved to:", output_filename, "\n")
  } else {
    cat("\n--- No results were processed successfully. ---\n")
  }

  return(final_summary)
}

convergence_results <- check_convergence(
  base_dir = CONFIG$BASE_DIR,
  sim_id = CONFIG$SIM_ID_TO_CHECK
)

cat("\nFinal Convergence Summary:\n")
print(convergence_results)
