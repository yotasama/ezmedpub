#' Check elements that are not numeric
#' @description Finds the elements that cannot be converted to numeric in a character vector.
#'   Useful when setting the strategy to clean numeric values.
#' @param x A string vector that stores numerical values.
#' @param return_idx A logical value. If TRUE, return the index of the elements that are not numeric.
#' @param show_unique A logical value. If TRUE, return the unique elements that are not numeric.
#'   Omitted if `return_idx` is TRUE.
#' @details The function uses the `as.numeric()` function to try to convert the elements to numeric.
#'   If the conversion fails, the element is considered non-numeric.
#' @return The (unique) elements that cannot be converted to numeric, and their indexes if `return_idx` is TRUE.
#' @export
#' @examples
#' check_nonnum(c("１２３", "11..23", "11ａ：","2.131","35.2."))
check_nonnum <- function(x, return_idx = F, show_unique = T) {
  x2 <- suppressWarnings(as.numeric(x))
  idx <- which(!is.na(x) & is.na(x2))
  y <- x[idx]
  if (return_idx) {
    list(value = y, idx = idx)
  } else if (show_unique) {
    unique(y)
  } else {
    y
  }
}
