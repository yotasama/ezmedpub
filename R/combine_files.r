#' combine multiple data files into a single dataframe
#'
#' @param path A string as the path to find the data files.
#' @param pattern A file pattern to filter the required data files.
#' @param unique_only A logical value to indicate whether to remove the duplicated rows.
#' @param reader_fun A function to read the data files. Can be `read.csv`, `openxlsx::read.xlsx`, etc.
#' @param ... Other parameters passed to the `reader_fun`.
#'
#' @returns A data frame. If no data files found, return `NULL`.
#' @export

combine_files <- function(path = ".", pattern = NULL, unique_only = TRUE, reader_fun = read.csv, ...) {
  files <- list.files(path = path, pattern = pattern, full.names = TRUE)
  if (length(files) > 0) {
    for (f in files) {
      tmp <- reader_fun(f, ...)
      if (f == files[1]) {
        dat <- tmp
      } else {
        dat <- rbind(dat, tmp)
      }
    }
    if (unique_only) {
      dat <- unique(dat)
    }
    return(dat)
  } else {
    return(NULL)
  }
}
