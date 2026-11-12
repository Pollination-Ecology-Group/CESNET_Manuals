# ==============================================================================
# s3_example.R — Reading and Writing Data on CESNET S3 Directly from R
# ==============================================================================
# This script demonstrates how to list, download, read, and upload files
# (CSV, RDS, images) directly between R and CESNET S3 ("peg-bucket") without
# needing to mount the bucket locally.
#
# Recommended setup for credentials:
#   Put your credentials in ~/.Renviron (run `usethis::edit_r_environ()` in R)
#   and add these lines:
#     AWS_ACCESS_KEY_ID="your_access_key_here"
#     AWS_SECRET_ACCESS_KEY="your_secret_key_here"
#     AWS_S3_ENDPOINT="s3.cl4.du.cesnet.cz"
#     AWS_DEFAULT_REGION=""
# ==============================================================================

# 1. Install aws.s3 if not already installed
if (!requireNamespace("aws.s3", quietly = TRUE)) {
  install.packages("aws.s3", repos = "https://cloud.r-project.org")
}
library(aws.s3)

# 2. Configure CESNET S3 connection parameters
# IMPORTANT: For non-Amazon Ceph S3 endpoints like CESNET, always set:
#   - base_url = "s3.cl4.du.cesnet.cz" (without https://)
#   - region = "" (empty string prevents aws.s3 from prepending us-east-1 to the URL!)
#   - use_https = TRUE
S3_BUCKET   <- Sys.getenv("S3_BUCKET", unset = "peg-bucket")
S3_BASE_URL <- "s3.cl4.du.cesnet.cz"

# Check that credentials are set in the environment
if (Sys.getenv("AWS_ACCESS_KEY_ID") == "" || Sys.getenv("AWS_SECRET_ACCESS_KEY") == "") {
  stop(
    "Missing S3 credentials! Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY ",
    "in your ~/.Renviron file or via Sys.setenv()."
  )
}

# ------------------------------------------------------------------------------
# Example A: List files under a specific folder (prefix) in the bucket
# ------------------------------------------------------------------------------
cat("Listing files in s3://", S3_BUCKET, "/Ostatni/ ...\n", sep = "")

bucket_contents <- get_bucket_df(
  bucket   = S3_BUCKET,
  prefix   = "Ostatni/",
  max      = 50,
  base_url = S3_BASE_URL,
  region   = "",
  use_https = TRUE
)

print(head(bucket_contents[, c("Key", "Size", "LastModified")], 10))

# ------------------------------------------------------------------------------
# Example B: Save an R object (.rds) or data.frame (.csv) directly to S3
# ------------------------------------------------------------------------------
demo_df <- data.frame(
  site_id = c("Handrkov_01", "Handrkov_02", "Handrkov_03"),
  pollinator_visits = c(42L, 19L, 67L),
  timestamp = Sys.time()
)

# Option 1: Save directly in memory as an .rds object on S3 via s3saveRDS()
# (Replace "Ostatni/sandbox/demo_results.rds" with your own folder path)
if (FALSE) {
  s3saveRDS(
    x        = demo_df,
    bucket   = S3_BUCKET,
    object   = "Ostatni/sandbox/demo_results.rds",
    base_url = S3_BASE_URL,
    region   = "",
    use_https = TRUE
  )

  # Read the .rds object back into R memory directly from S3:
  loaded_df <- s3readRDS(
    bucket   = S3_BUCKET,
    object   = "Ostatni/sandbox/demo_results.rds",
    base_url = S3_BASE_URL,
    region   = "",
    use_https = TRUE
  )
  print(loaded_df)
}

# ------------------------------------------------------------------------------
# Example C: Download a file from S3 to a local path & Upload a local file to S3
# ------------------------------------------------------------------------------
if (FALSE) {
  # Upload a local file (e.g., a plot PDF or CSV) to S3:
  put_object(
    file     = "local_output.csv",
    object   = "Ostatni/sandbox/local_output.csv",
    bucket   = S3_BUCKET,
    base_url = S3_BASE_URL,
    region   = "",
    use_https = TRUE,
    multipart = TRUE
  )

  # Download a file from S3 to your local working directory:
  save_object(
    object   = "Ostatni/sandbox/local_output.csv",
    bucket   = S3_BUCKET,
    file     = "downloaded_output.csv",
    base_url = S3_BASE_URL,
    region   = "",
    use_https = TRUE
  )
}

