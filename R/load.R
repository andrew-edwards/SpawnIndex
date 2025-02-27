#' Load Pacific Herring areas.
#'
#' Load Pacific Herring areas. Herring areas are kept in two files: the section
#' file has coarse area information, and location file has finer details. This
#' function merges these two files, and drops unnecessary rows and columns. In
#' addition, 'groups' are created for certain regions based on section numbers.
#' The output is a data frame with both coarse- and fine-scale area information
#' for the region(s) in question. There is an option to subset the sections if
#' desired.
#'
#' @param reg Character. Region of interest (see \code{\link{regions}}).
#' @param sec_sub Numeric vector or NULL. Subset of Sections to include in the
#'   analysis, or NULL to include all the Sections in the region.
#' @template param-where
#' @param in_crs Character. Input coordinate reference system;
#'   \href{https://spatialreference.org/}{use EPSG codes if desired}.
#' @param out_crs Character. Output coordinate reference system;
#'   \href{https://spatialreference.org/}{use EPSG codes if desired}.
#' @param groups Tibble or NULL. Optional table to add a "Group" column to the
#'   results, say to aggregate data by combinations of Sections. Must have a
#'   column named "Group", and one or more of "StatArea", "Section",
#'   "LocationCode". Set to NULL to ignore (and Group column will be NA).
#' @param region_table Tibble. Cross-walk table for regions and region names;
#'   from \code{\link{regions}}.
#' @template param-quiet
#' @importFrom readr read_csv cols
#' @importFrom dplyr filter select mutate full_join %>% transmute right_join
#'   distinct
#' @importFrom tidyr unite
#' @importFrom odbc dbConnect odbc dbDisconnect
#' @importFrom DBI dbReadTable
#' @importFrom tibble as_tibble is_tibble
#' @importFrom sp SpatialPoints spTransform CRS
#' @importFrom Rdpack reprompt
#' @return Tibble. Table of geographic information for Pacific Herring: SAR,
#'   Region, Region name, Statistical Area, Group, Section, Location code,
#'   Location name, Pool, Eastings, Northings, Longitude, and Latitude.
#' @seealso \code{\link{HerringSpawn}} \code{\link{regions}}
#' @family load functions
#' @note This function requires 32-bit R to load data from the 32-bit MS Access
#'   database.
#' @export
#' @examples
#' data(regions)
#' db_loc <- system.file("extdata", package = "SpawnIndex")
#' area_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(sections = "Sections", locations = "Location")
#' )
#' areas <- load_area_data(reg = "WCVI", where = area_loc)
#' areas
#' secs <- c(231:233, 241, 245)
#' grps <- tibble::tibble(
#'   Section = c(231, 232, 233, 241),
#'   Group = c("Alberni Int", "Barkley", "Barkley", "Tofino Int")
#' )
#' areas_sec_grp <- load_area_data(
#'   reg = "WCVI", where = area_loc, groups = grps, sec_sub = secs
#' )
#' dplyr::distinct(dplyr::select(
#'   areas_sec_grp, Region, StatArea, Group, Section
#' ))
load_area_data <- function(reg,
                           sec_sub = NULL,
                           where,
                           in_crs = "+init=epsg:4326",
                           out_crs = "+init=epsg:3005",
                           groups = NULL,
                           region_table = regions,
                           quiet = FALSE) {
  # Check reg: character
  if (!is.character(reg)) stop("`reg` must be character.", call. = FALSE)
  # Check sec_sub: numeric or null
  if (!is.numeric(sec_sub) & !is.null(sec_sub)) {
    stop("`sec_sub` must be numeric or NULL.", call. = FALSE)
  }
  # Check where
  check_where(
    dat = where, dat_names = c("loc", "db", "fns.sections", "fns.locations")
  )
  # Check in_crs and out_crs: character
  if (!is.character(in_crs) & !is.character(out_crs)) {
    stop("`in_crs` and `out_crs` must be characters.")
  }
  # Check groups: tibble or NULL
  if (is_tibble(groups)) {
    # Check group names
    if (!"Group" %in% names(groups)) {
      stop("`groups` needs column named 'Group`", call. = FALSE)
    }
    if (!any(c("StatArea", "Section", "LocationCode") %in% names(groups))) {
      stop("`groups` needs column named `StatArea`, `Section`, and/or
           LocationCode", call. = FALSE)
    }
  } else {
    # If not tibble, must be NULL
    if (!is.null(groups)) stop("`groups` must be tibble or NULL.")
  }
  # If region isn't JS, remove it
  if (!reg %in% c("JS", "All")) {
    region_table <- region_table %>%
      filter(SAR != 8)
  }
  # Error if region is incorrect
  if (!(reg %in% c(region_table$Region, "All"))) {
    stop(
      "Possible regions are: ", paste_nicely(region_table$Region), ".",
      call. = FALSE
    )
  }
  # Establish connection with access
  access_db <- dbConnect(
    drv = odbc(),
    .connection_string = paste(
      "Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=",
      file.path(where$loc, where$db),
      sep = ""
    )
  )
  # Access the sections worksheet
  sections <- dbReadTable(conn = access_db, name = where$fns$sections)
  # Error if data was not fetched
  if (class(sections) != "data.frame") {
    stop("No data available in MS Access connection.", call. = FALSE)
  }
  # Check sections: names
  if (!all(c("SAR", "Section") %in% names(sections))) {
    stop("Sections table is missing columns", call. = FALSE)
  }
  # Is it a special region?
  reg_type <- region_table$Type[which(region_table$Region == reg)]
  # Fix if region is All
  if (reg == "All" & length(reg_type) == 0) reg_type <- ""
  # If the region is special
  if (reg_type == "Special") {
    # TODO: Sections 132 and 135 are also SoG sections -- how to resolve?
    # Manual fix: Johnstone Strait herring sections
    if (reg == "JS") special_sections <- c(111, 112, 121:127, 131:136)
    if (reg == "A10") special_sections <- c(101:103)
    # Message
    if (!quiet) {
      cat("Note that this is a special SAR, not an official SAR.")
      if (reg == "JS") {
        cat("Sections 132 and 135 are in SoG.\n")
      }
      if (reg == "A10") {
        cat("Sections 101, 102, and 103 are in CC.\n")
      }
    }
    # Get the region number from the table
    reg_num <- region_table$SAR[which(region_table$Region == reg)]
    # Wrangle the sections worksheet
    sections <- sections %>%
      filter(Section %in% special_sections) %>%
      mutate(SAR = reg_num) %>%
      full_join(y = region_table, by = "SAR") %>%
      filter(Region %in% reg) %>%
      select(SAR, Region, RegionName, Section) %>%
      mutate(Section = as.integer(Section)) %>%
      distinct() %>%
      as_tibble()
  } else { # End if special, otherwise
    # Wrangle the sections table
    sections <- sections %>%
      full_join(y = region_table, by = "SAR") %>%
      select(SAR, Region, RegionName, Section) %>%
      mutate(Section = as.integer(Section)) %>%
      distinct() %>%
      as_tibble()
    # If we only want a specific region
    if (reg != "All") {
      # Remove areas outside SARs, and other regions
      sections <- sections %>%
        filter(SAR != -1, Region == reg)
    } # End if we only want a specific region
  } # End if the region is not Johnstone Strait
  # Access the locations worksheet
  loc <- dbReadTable(conn = access_db, name = where$fns$locations)
  # Error if data was not fetched
  if (class(loc) != "data.frame") {
    stop("No data available in MS Access connection.", call. = FALSE)
  }
  # Check loc: names
  if (!all(c(
    "Loc_Code", "Location", "StatArea", "Section", "Bed", "Location_Latitude",
    "Location_Longitude"
  ) %in% names(loc))) {
    stop("Locations table is missing columns", call. = FALSE)
  }
  # Wrangle the locations table
  loc_dat <- as_tibble(loc) %>%
    select(
      Loc_Code, Location, StatArea, Section, Bed, Location_Latitude,
      Location_Longitude
    ) %>%
    mutate(Location = as.character(Location)) %>%
    rename(
      LocationCode = Loc_Code, LocationName = Location,
      Latitude = Location_Latitude, Longitude = Location_Longitude, Pool = Bed
    ) %>%
    replace_na(replace = list(Longitude = 0, Latitude = 0)) %>%
    select(
      LocationCode, LocationName, Pool, Section, StatArea, Longitude,
      Latitude
    ) %>%
    arrange(LocationCode) %>%
    distinct()
  # Grab the spatial info (X and Y)
  loc_sp <- loc_dat %>%
    transmute(X = Longitude, Y = Latitude)
  # Put X and Y into a spatial points object
  loc_pts <- SpatialPoints(coords = loc_sp, proj4string = CRS(in_crs))
  # Convert X and Y from WGS to Albers
  loc_pts_alb <- spTransform(x = loc_pts, CRSobj = CRS(out_crs))
  # Extract spatial info
  df_alb <- as_tibble(loc_pts_alb)
  # Extract relevant location data
  locations <- loc_dat %>%
    cbind(df_alb) %>%
    mutate(
      Eastings = ifelse(is.na(Longitude), Longitude, X),
      Northings = ifelse(is.na(Latitude), Latitude, Y),
      Section = as.integer(Section)
    ) %>%
    select(
      StatArea, Section, LocationCode, LocationName, Pool, Eastings,
      Northings, Latitude, Longitude
    ) %>%
    filter(Section %in% sections$Section) %>%
    distinct() %>%
    as_tibble()
  # If groups is NULL
  if (is.null(groups)) {
    # Set groups to NA
    locations <- locations %>%
      mutate(Group = NA)
  } else { # End if NULL, otherwise
    # Determine matching columns
    grp_cols <- which(names(groups) %in% names(locations))
    # Set groups
    locations <- locations %>%
      left_join(y = groups, by = names(groups)[grp_cols])
  } # End if not NULL
  # If any groups are NA, check if *some* are missing (i.e., incomplete)
  if (any(is.na(locations$Group))) {
    # Get distinct rows
    grp_u <- locations %>%
      select(StatArea, Section, Group) %>%
      distinct() %>%
      arrange(StatArea, Section)
    # Get distinct rows with no missing groups
    grp_u_na <- grp_u %>%
      filter(is.na(Group))
    # Check if none or all have groups
    none_or_all <- nrow(grp_u) == nrow(grp_u_na)
    # Message re some sections(s) missing group info
    if (!none_or_all & !quiet) {
      cat("Incomplete `Group' info for Section(s): ",
        paste_nicely(unique(grp_u_na$Section)), "\n",
        sep = ""
      )
    }
  } # End if any groups are NA
  # Extract required data
  res <- locations %>%
    right_join(y = sections, by = "Section") %>%
    filter(!is.na(StatArea), !is.na(Section)) %>%
    select(
      SAR, Region, RegionName, StatArea, Group, Section, LocationCode,
      LocationName, Pool, Eastings, Northings, Longitude, Latitude
    ) %>%
    mutate(Section = as.integer(Section), Pool = as.integer(Pool)) %>%
    #      mutate( StatArea=formatC(StatArea, width=2, format="d", flag="0"),
    #          Section=formatC(Section, width=3, format="d", flag="0") ) %>%
    arrange(Region, StatArea, Group, Section, LocationCode) %>%
    distinct() %>%
    droplevels()
  # If not all sections are included
  if (!is.null(sec_sub)) {
    # Grab a subset of sections
    res <- res %>%
      filter(Section %in% sec_sub) %>%
      droplevels()
    # Message
    if (!quiet) {
      cat("Sections: ", paste_nicely(sec_sub), "\n", sep = "")
    }
  } # End if subsetting sections
  # Close the connection
  dbDisconnect(conn = access_db)
  # Check output: tibble rows
  check_tibble(dat = list(res = res), quiet = quiet)
  # Check output: names
  if (!all(c(
    "SAR", "Region", "RegionName", "StatArea", "Group", "Section",
    "LocationCode", "LocationName", "Pool", "Eastings", "Northings",
    "Longitude", "Latitude"
  ) %in% names(res))) {
    stop("`res` is missing columns", call. = FALSE)
  }
  # Return herring areas
  res
} # End load_area_data function

#' Load the all spawn table.
#'
#' Load the all spawn table, which has additional spawn survey data.
#'
#' @template param-where
#' @template param-areas
#' @template param-years
#' @param ft2m Numeric. Conversion factor for feet to metres; default is 0.3048.
#'   Message if not 0.3048.
#' @template param-quiet
#' @importFrom odbc dbConnect odbc dbDisconnect
#' @importFrom DBI dbReadTable
#' @importFrom dplyr select rename full_join filter mutate %>% arrange ungroup
#'   distinct
#' @importFrom tibble as_tibble
#' @importFrom stringr str_to_title
#' @importFrom lubridate as_date
#' @importFrom gfiscamutils max_na
#' @importFrom Rdpack reprompt
#' @return Tibble. Contains additional spawn survey data including start and end
#'   dates, as well as spawn length, width, and depth. Other information in this
#'   tibble comes from \code{a}: Region, Statistical Area, Section, and Location
#'   code.
#' @seealso \code{\link{HerringSpawn}} \code{\link{load_area_data}}
#' @family load functions
#' @export
#' @examples
#' db_loc <- system.file("extdata", package = "SpawnIndex")
#' area_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(sections = "Sections", locations = "Location")
#' )
#' areas <- load_area_data(reg = "WCVI", where = area_loc)
#' all_spawn_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(all_spawn = "tSSAllspawn", stations = "tSSStations")
#' )
#' all_spawn <- load_all_spawn(
#'   where = all_spawn_loc, areas = areas, years = 2010:2015
#' )
#' all_spawn
load_all_spawn <- function(where,
                           areas,
                           years,
                           ft2m = 0.3048,
                           quiet = FALSE) {
  # Check where
  check_where(
    dat = where, dat_names = c("loc", "db", "fns.all_spawn", "fns.stations")
  )
  # Check input: tibble rows
  check_tibble(dat = list(areas = areas), quiet = quiet)
  # Check areas: names
  if (!all(c(
    "Region", "StatArea", "Group", "Section", "LocationCode", "LocationName",
    "Eastings", "Northings", "Longitude", "Latitude"
  ) %in% names(areas))) {
    stop("`areas` is missing columns", call. = FALSE)
  }
  # Check input: NA and numeric
  check_numeric(
    dat = list(years = years, ft2m = ft2m),
    quiet = quiet
  )
  # Check years: range
  if (any(years < pars$years$assess) & !quiet) {
    message("`years` < ", pars$years$assess, ".")
  }
  # Check ft2m: range
  if (!all.equal(ft2m, 0.3048, 0.00001) & !quiet) {
    message("`ft2m` is not 0.3048.")
  }
  # Get a small subset of area data
  areas_sm <- areas %>%
    select(
      Region, StatArea, Group, Section, LocationCode, LocationName, Eastings,
      Northings, Longitude, Latitude
    ) %>%
    distinct() %>%
    as_tibble()
  # Establish connection with access
  access_db <- dbConnect(
    drv = odbc(),
    .connection_string = paste(
      "Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=",
      file.path(where$loc, where$db),
      sep = ""
    )
  )
  # Extract relevant spawn data
  spawn <- dbReadTable(conn = access_db, name = where$fns$all_spawn) %>%
    rename(LocationCode = Loc_Code, SpawnNumber = Spawn_Number) %>%
    mutate(
      Start = as_date(Start), End = as_date(End),
      Method = str_to_title(Method)
    ) %>%
    filter(Year %in% years, LocationCode %in% areas_sm$LocationCode) %>%
    select(
      Year, LocationCode, SpawnNumber, Start, End, Length, Width, Method
    ) %>%
    as_tibble()
  # Extrac relevant stations data
  stations <- dbReadTable(conn = access_db, name = where$fns$stations) %>%
    rename(LocationCode = Loc_Code, SpawnNumber = Spawn_Number) %>%
    filter(LocationCode %in% areas_sm$LocationCode) %>%
    mutate(DepthM = Depth * ft2m * -1) %>%
    group_by(Year, LocationCode, SpawnNumber) %>%
    summarise(Depth = max_na(DepthM)) %>%
    ungroup() %>%
    arrange(Year, LocationCode, SpawnNumber)
  # Combine spawn and station data
  spawn_station <- full_join(
    x = spawn, y = stations,
    by = c("Year", "LocationCode", "SpawnNumber")
  )
  # Combine spawn and station data with area data
  res <- spawn_station %>%
    left_join(y = areas_sm, by = c("LocationCode")) %>%
    select(
      Year, Region, StatArea, Group, Section, LocationCode, LocationName,
      SpawnNumber, Eastings, Northings, Longitude, Latitude, Start, End,
      Length, Width, Depth, Method
    ) %>%
    arrange(
      Year, Region, StatArea, Section, LocationCode, SpawnNumber, Start
    )
  # Close the connection
  dbDisconnect(conn = access_db)
  # Check output: tibble rows
  check_tibble(dat = list(res = res), quiet = quiet)
  # Check output: names
  if (!all(c(
    "Year", "Region", "StatArea", "Group", "Section", "LocationCode",
    "LocationName", "SpawnNumber", "Eastings", "Northings", "Longitude",
    "Latitude", "Start", "End", "Length", "Width", "Depth", "Method"
  ) %in% names(res))) {
    stop("`res` is missing columns", call. = FALSE)
  }
  # Return the table
  res
} # End load_all_spawn function

#' Load median spawn width.
#'
#' Load median spawn width in metres (m) for Pacific Herring surface spawn index
#' calculations. Observed width is not preferred for surface spawn surveys
#' because surveyors tend to underestimate spawn width
#' \insertCite{HayKronlund1987}{SpawnIndex}. Instead, the preferred with comes
#' from underwater surveys \insertCite{GrinnellEtalYYYY}{SpawnIndex}.
#'
#' @template param-where
#' @template param-areas
#' @template param-quiet
#' @importFrom odbc dbConnect odbc dbDisconnect
#' @importFrom DBI dbReadTable
#' @importFrom dplyr select distinct rename left_join filter %>%
#' @importFrom tibble as_tibble
#' @importFrom Rdpack reprompt
#' @return List with three tables: median region (\code{WidthReg}), section
#'   (\code{WidthSec}), and pool (\code{WidthPool}) widths in metres (m) for the
#'   areas in \code{a}.
#' @references \insertAllCited
#' @seealso \code{\link{HerringSpawn}} \code{\link{load_area_data}}
#'   \code{\link{calc_surf_index}}
#' @family load functions
#' @export
#' @examples
#' db_loc <- system.file("extdata", package = "SpawnIndex")
#' area_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(sections = "Sections", locations = "Location")
#' )
#' areas <- load_area_data(reg = "WCVI", where = area_loc)
#' width_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(
#'     region_std = "RegionStd", section_std = "SectionStd",
#'     pool_std = "PoolStd"
#'   )
#' )
#' width_bar <- load_width(where = width_loc, areas = areas)
#' width_bar
load_width <- function(where,
                       areas,
                       quiet = FALSE) {
  # Check where
  check_where(dat = where, dat_names = c(
    "loc", "db", "fns.region_std", "fns.section_std", "fns.pool_std"
  ))
  # Check input: tibble rows
  check_tibble(dat = list(areas = areas), quiet = quiet)
  # Check areas: names
  if (!all(c("SAR", "Region", "StatArea", "Section", "LocationCode", "Pool")
  %in% names(areas))) {
    stop("`areas` is missing columns", call. = FALSE)
  }
  # Get area info
  areas_sm <- areas %>%
    select(SAR, Region, StatArea, Section, LocationCode, Pool) %>%
    distinct() %>%
    as_tibble()
  # Establish connection with access
  access_db <- dbConnect(
    drv = odbc(),
    .connection_string = paste(
      "Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=",
      file.path(where$loc, where$db),
      sep = ""
    )
  )
  # Access the region worksheet and wrangle
  reg_std <- dbReadTable(conn = access_db, name = where$fns$region_std) %>%
    rename(SAR = REGION, WidthReg = WIDMED) %>%
    left_join(y = areas_sm, by = "SAR") %>%
    filter(SAR %in% areas_sm$SAR) %>%
    select(Region, WidthReg) %>%
    distinct() %>%
    as_tibble()
  # Access the section worksheet and wrangle
  sec_std <- dbReadTable(conn = access_db, name = where$fns$section_std) %>%
    rename(Section = SECTION, WidthSec = WIDMED) %>%
    mutate(Section = as.integer(Section)) %>%
    left_join(y = areas_sm, by = "Section") %>%
    filter(Section %in% areas_sm$Section) %>%
    select(Region, Section, WidthSec) %>%
    distinct() %>%
    as_tibble()
  # Access the pool worksheet and wrangle
  pool_std <- dbReadTable(conn = access_db, name = where$fns$pool_std) %>%
    rename(Section = SECTION, Pool = BED, WidthPool = WIDMED) %>%
    mutate(Section = as.integer(Section), Pool = as.integer(Pool)) %>%
    left_join(y = areas_sm, by = c("Section", "Pool")) %>%
    filter(Section %in% areas_sm$Section) %>%
    select(Region, Section, Pool, WidthPool) %>%
    distinct() %>%
    as_tibble()
  # Merge the tables to a list
  res <- list(region = reg_std, section = sec_std, pool = pool_std)
  # Close the connection
  dbDisconnect(conn = access_db)
  # Check output: tibble rows
  check_tibble(
    dat = list(region = res$region, section = res$section, pool = res$pool),
    quiet = quiet
  )
  # Check output: region names
  if (!all(c("Region", "WidthReg") %in% names(res$region))) {
    stop("`res$region` is missing columns", call. = FALSE)
  }
  # Check output: section names
  if (!all(c("Region", "Section", "WidthSec") %in% names(res$section))) {
    stop("`res$section` is missing columns", call. = FALSE)
  }
  # Check output: pool names
  if (!all(c("Region", "Section", "Pool", "WidthPool") %in% names(res$pool))) {
    stop("`res$pool` is missing columns", call. = FALSE)
  }
  # Table to return
  res
} # End load_width function

#' Load and wrangle Pacific Herring Section shapefiles.
#'
#' Load and wrangle Pacific Herring Section shapefiles, and aggregate to
#' Statistical Areas and Region(s).
#'
#' @param sections Simple feature collection of polygons; from
#'   \code{\link{sections}}.
#' @template param-areas
#' @param subset Logical. Subset sections to those in \code{areas}. Default
#'   TRUE.
#' @param buffer Numeric. Buffer around polygons; distance in metres. Default
#'   5000.
#' @param out_crs Numeric. Target coordinate reference system. Default
#'   \href{https://spatialreference.org/ref/epsg/wgs-84/}{4326}.
#' @template param-quiet
#' @importFrom sf st_read st_bbox st_buffer st_transform
#' @return List of spatial objects showing Section, Group, Statistical Area, and
#'   Region boundaries.
#' @references \insertAllCited
#' @seealso \code{\link{sections}}
#' @family load functions
#' @export
#' @examples
#' db_loc <- system.file("extdata", package = "SpawnIndex")
#' area_loc <- list(
#'   loc = db_loc, db = "HerringSpawn.mdb",
#'   fns = list(sections = "Sections", locations = "Location")
#' )
#' areas <- load_area_data(reg = "WCVI", where = area_loc)
#' polys <- load_sections(sections = sections, areas = areas)
load_sections <- function(sections,
                          areas,
                          subset = TRUE,
                          buffer = 5000,
                          out_crs = 4326,
                          quiet = FALSE) {
  # Check input: tibble rows
  check_tibble(dat = list(areas = areas), quiet = quiet)
  # Check areas: names
  if (!all(c("SAR", "Region", "StatArea", "Group", "Section")
  %in% names(areas))) {
    stop("`areas` is missing columns", call. = FALSE)
  }
  # Check input: NA and numeric
  check_numeric(dat = list(buffer = buffer, out_crs = out_crs), quiet = quiet)
  # Check buffer: range
  if (any(na.omit(buffer) < 0) & !quiet) message("`buffer` < 0.")
  # Get area information
  areas_sm <- areas %>%
    select(SAR, Region, StatArea, Group, Section) %>%
    distinct() %>%
    mutate(
      StatArea = formatC(StatArea, width = 2, flag = "0"),
      Section = formatC(Section, width = 3, flag = "0")
    ) %>%
    arrange(SAR, StatArea, Group, Section)
  # Subset to sections in areas
  if (subset) {
    sections <- sections %>%
      filter(Section %in% areas$Section) %>%
      left_join(y = areas_sm, by = "Section")
  } else { # End if subset, otherwise
    sections <- sections %>%
      left_join(y = areas_sm, by = "Section")
  } # End if no subset
  # Dissolve to Groups
  groups <- sections %>%
    group_by(Group) %>%
    summarise() %>%
    ungroup() %>%
    st_transform(crs = out_crs)
  # Dissolve to statistical area
  stat_areas <- sections %>%
    group_by(Region, StatArea) %>%
    summarise() %>%
    ungroup() %>%
    st_transform(crs = out_crs)
  # Dissolve to region
  regions <- sections %>%
    group_by(Region) %>%
    summarise() %>%
    ungroup()
  # Get a buffer around the region(s) in question
  buff <- regions %>%
    st_buffer(dist = buffer) %>%
    st_bbox()
  # Determine x:y aspect ratio (for plotting)
  xy_ratio <- as.numeric((buff$xmax - buff$xmin) / (buff$ymax - buff$ymin))
  # Transform sections
  sections <- sections %>%
    st_transform(crs = out_crs)
  # Transform regions
  regions <- regions %>%
    st_transform(crs = out_crs)
  # Return the spatial objects etc
  return(list(
    sections = sections, groups = groups, stat_areas = stat_areas,
    regions = regions, xy_ratio = xy_ratio
  ))
} # End load_sections function
