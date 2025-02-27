% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data.R
\docType{data}
\name{intensity}
\alias{intensity}
\title{Spawn intensity categories and number of egg layers.}
\format{
Tibble with 9 rows and 3 columns: intensity category, description,
and number of egg layers.
}
\usage{
intensity
}
\description{
Spawn intensity categories and number of egg layers for Pacific Herring
surface spawn surveys. From 1928 to
1978, surface spawn surveyors categorized spawn by
subjective 'intensity' categories instead of directly estimating the number
of egg layers
\insertCite{HayKronlund1987,SchweigertStocker1988,GrinnellEtalYYYY}{SpawnIndex}.
Surveyors used five categories from 1928 to
1968, and then nine categories from
1969 to 1978.
}
\examples{
data(intensity)
intensity
}
\references{
\insertAllCited{}
}
\seealso{
\code{\link{calc_surf_index}}

Other data: 
\code{\link{algae_coefs}},
\code{\link{pars}},
\code{\link{regions}},
\code{\link{sections}},
\code{\link{under_width_facs}}
}
\concept{data}
\keyword{datasets}
