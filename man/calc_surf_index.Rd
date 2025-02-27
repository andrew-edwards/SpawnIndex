% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/calcs.R
\name{calc_surf_index}
\alias{calc_surf_index}
\title{Calculate the surface spawn index.}
\usage{
calc_surf_index(
  where,
  areas,
  widths,
  years,
  intense = intensity,
  intense_yrs = pars$years$survey:(pars$years$layers - 1),
  rescale_yrs = pars$years$survey:(pars$years$assess - 1),
  alpha = pars$surface$alpha,
  beta = pars$surface$beta,
  theta = eggs_to_sb(),
  quiet = FALSE
)
}
\arguments{
\item{where}{List. Location and name of the Pacific Herring spawn survey
database, as well as required tables (see examples).}

\item{areas}{Tibble. Table of geographic information indicating the subset of
observations to include; from \code{\link{load_area_data}}.}

\item{widths}{List. List of three tables: median region, section, and pool
widths in metres (m); from \code{\link{load_width}}.}

\item{years}{Numeric vector. Years(s) to include in the calculations. Message
if < \code{pars$years$assess}.}

\item{intense}{Tibble. Table of spawn intensity categories and number of egg
layers; from \code{\link{intensity}}.}

\item{intense_yrs}{Numeric vector. Years where intensity categories are used
to determine egg layers. Message if >= \code{pars$years$layers}.}

\item{rescale_yrs}{Numeric vector. Years where intensity needs to be
re-scaled from 5 to 9 categories. Message if >= \code{pars$years$assess}.}

\item{alpha}{Numeric. Regression intercept; from \code{\link{pars}}
\insertCite{SchweigertEtal1997}{SpawnIndex}.}

\item{beta}{Numeric. Regression slope; from \code{\link{pars}}
\insertCite{SchweigertEtal1997}{SpawnIndex}.}

\item{theta}{Numeric. Egg conversion factor (eggs to biomass); from
\code{\link{eggs_to_sb}}. Message if < 0.}

\item{quiet}{Logical. Suppress messages; default is FALSE.}
}
\value{
List. The element \code{si} is a tibble with surface spawn index
(\code{SurfSI}) in tonnes by spawn number and year. The spawn number is the
finest spatial scale at which we calculate the spawn index. Other
information in this tibble comes from \code{a}: Region, Statistical Area,
Section, and Location code.
}
\description{
Calculate the Pacific Herring surface spawn index in tonnes
\insertCite{SchweigertEtal1997}{SpawnIndex}. This function primarily wrangles
and prepares the data; the actual calculation is done by
\code{\link{dens_surf}}.
}
\note{
The `spawn index' is a relative index of spawning biomass.
}
\examples{
db_loc <- system.file("extdata", package = "SpawnIndex")
area_loc <- list(
  loc = db_loc, db = "HerringSpawn.mdb",
  fns = list(sections = "Sections", locations = "Location")
)
areas <- load_area_data(reg = "WCVI", where = area_loc)
width_loc <- list(
  loc = db_loc, db = "HerringSpawn.mdb",
  fns = list(
    region_std = "RegionStd", section_std = "SectionStd",
    pool_std = "PoolStd"
  )
)
width_bar <- load_width(where = width_loc, a = areas)
data(pars)
data(intensity)
surf_loc <- list(
  loc = db_loc, db = "HerringSpawn.mdb",
  fns = list(surface = "tSSSurface", all_spawn = "tSSAllspawn")
)
surf_spawn <- calc_surf_index(
  where = surf_loc, areas = areas, widths = width_bar, years = 2010:2015
)
surf_spawn$si
}
\references{
\insertAllCited
}
\seealso{
\code{\link{HerringSpawn}} \code{\link{load_area_data}}
\code{\link{load_width}} \code{\link{eggs_to_sb}}
\code{\link{pars}} \code{\link{intensity}} \code{\link{dens_surf}}

Other calculation functions: 
\code{\link{calc_macro_index}()},
\code{\link{calc_sok_index}()},
\code{\link{calc_under_index}()},
\code{\link{dens_surf}()},
\code{\link{dens_under_alg}()},
\code{\link{dens_under_sub}()},
\code{\link{eggs_macro}()},
\code{\link{eggs_to_sb}()}
}
\concept{calculation functions}
