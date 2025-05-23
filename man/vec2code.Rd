% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/misc.r
\name{vec2code}
\alias{vec2code}
\title{Generate code from string vector
Generate the code that can be used to generate the string vector.}
\usage{
vec2code(x)
}
\arguments{
\item{x}{A string vector.}
}
\value{
A string that contains the code to generate the vector.
}
\description{
Generate code from string vector
Generate the code that can be used to generate the string vector.
}
\examples{
vec2code(colnames(mtcars))
}
