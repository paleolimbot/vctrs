context("test-type-date-time")

test_that("date-times have informative types", {
  expect_equal(vec_ptype_abbr(Sys.Date()), "date")
  expect_equal(vec_ptype_full(Sys.Date()), "date")

  expect_equal(vec_ptype_abbr(Sys.time()), "dttm")
  expect_equal(vec_ptype_full(Sys.time()), "datetime<local>")

  expect_equal(vec_ptype_abbr(new_duration(10)), "drtn")
  expect_equal(vec_ptype_full(new_duration(10)), "duration<secs>")
})

test_that("vec_ptype() returns a double date for integer dates", {
  x <- structure(0L, class = "Date")
  expect_true(is.double(vec_ptype(x)))
})

test_that("dates and times are vectors", {
  expect_true(vec_is(Sys.Date()))
  expect_true(vec_is(as.POSIXct("2020-01-01")))
  expect_true(vec_is(as.POSIXlt("2020-01-01")))
})

test_that("vec_c() converts POSIXct with int representation to double representation (#540)", {
  time1 <- seq(as.POSIXct("2015-12-01", tz = "UTC"), length.out = 2, by = "days")
  time2 <- vec_c(time1)
  expect_true(is.double(time2))

  time3 <- vec_c(time1, time1)
  expect_true(is.double(time3))
})

test_that("vec_c() and vec_rbind() convert Dates with int representation to double representation (#396)", {
  x <- structure(0L, class = "Date")
  df <- data.frame(x = x)

  expect_true(is.double(vec_c(x)))
  expect_true(is.double(vec_c(x, x)))

  expect_true(is.double(vec_rbind(df)$x))
  expect_true(is.double(vec_rbind(df, df)$x))
})

test_that("vec_proxy() returns a double for Dates with int representation", {
  x <- structure(0L, class = "Date")
  expect_true(is.double(vec_proxy(x)))
})

test_that("POSIXlt roundtrips through proxy and restore", {
  x <- as.POSIXlt("2020-01-03")
  out <- vec_restore(vec_proxy(x), x)
  expect_identical(out, x)
})


# coerce ------------------------------------------------------------------

test_that("datetime coercions are symmetric and unchanging", {
  types <- list(
    new_date(),
    new_datetime(),
    new_datetime(tzone = "US/Central"),
    as.POSIXlt(character(), tz = "US/Central"),
    difftime(Sys.time() + 1000, Sys.time()),
    difftime(Sys.time() + 1, Sys.time())
  )
  mat <- maxtype_mat(types)

  expect_true(isSymmetric(mat))
  expect_known_output(
    mat,
    test_path("test-type-date-time.txt"),
    print = TRUE,
    width = 200
  )
})

test_that("tz comes from first non-empty", {
  # On the assumption that if you've set the time zone explicitly it
  # should win

  x <- as.POSIXct("2020-01-01")
  y <- as.POSIXct("2020-01-01", tz = "America/New_York")

  expect_equal(vec_ptype2(x, y), y[0])
  expect_equal(vec_ptype2(y, x), y[0])

  z <- as.POSIXct("2020-01-01", tz = "Pacific/Auckland")
  expect_equal(vec_ptype2(y, z), y[0])
  expect_equal(vec_ptype2(z, y), z[0])
})

test_that("POSIXlt always steered towards POSIXct", {
  dtc <- as.POSIXct("2020-01-01")
  dtl <- as.POSIXlt("2020-01-01")

  expect_equal(vec_ptype2(dtc, dtl), dtc[0])
  expect_equal(vec_ptype2(dtl, dtc), dtc[0])
  expect_equal(vec_ptype2(dtl, dtl), dtc[0])
})

test_that("vec_ptype2() on a POSIXlt with multiple time zones returns the first", {
  x <- as.POSIXlt(new_datetime(), tz = "Pacific/Auckland")

  expect_identical(attr(x, "tzone"), c("Pacific/Auckland", "NZST", "NZDT"))
  expect_identical(attr(vec_ptype2(x, new_date()), "tzone"), "Pacific/Auckland")
})

test_that("vec_ptype2(<Date>, NA) is symmetric (#687)", {
  date <- new_date()
  expect_identical(
    vec_ptype2(date, NA),
    vec_ptype2(NA, date)
  )
})

test_that("vec_ptype2(<POSIXt>, NA) is symmetric (#687)", {
  time <- Sys.time()
  expect_identical(
    vec_ptype2(time, NA),
    vec_ptype2(NA, time)
  )
})

test_that("vec_ptype2(<difftime>, NA) is symmetric (#687)", {
  dtime <- Sys.time() - Sys.time()
  expect_identical(
    vec_ptype2(dtime, NA),
    vec_ptype2(NA, dtime)
  )
})


# cast: dates ---------------------------------------------------------------

test_that("safe casts work as expected", {
  date <- as.Date("2018-01-01")

  expect_equal(vec_cast(NULL, date), NULL)
  expect_equal(vec_cast(date, date), date)
  expect_equal(vec_cast(as.POSIXct(date), date), date)

  missing_date <- new_date(NA_real_)

  expect_equal(vec_cast(missing_date, missing_date), missing_date)
  expect_equal(vec_cast(as.POSIXct(missing_date), missing_date), missing_date)
  expect_equal(vec_cast(as.POSIXlt(missing_date), missing_date), missing_date)

  # These used to be allowed
  expect_error(vec_cast(17532, date), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast("2018-01-01", date), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast(list(date), date), class = "vctrs_error_incompatible_type")
})

test_that("lossy casts generate error", {
  date <- as.Date("2018-01-01")
  datetime <- as.POSIXct(date) + c(0, 3600)
  expect_lossy(vec_cast(datetime, date), vec_c(date, date), x = datetime, to = date)
})

test_that("invalid casts generate error", {
  date <- as.Date("2018-01-01")
  expect_error(vec_cast(integer(), date), class = "vctrs_error_incompatible_type")
})

test_that("can cast NA and unspecified to Date", {
  expect_identical(vec_cast(NA, new_date()), new_date(NA_real_))
  expect_identical(vec_cast(unspecified(2), new_date()), new_date(dbl(NA, NA)))
})

test_that("casting an integer date to another date returns a double date", {
  x <- structure(0L, class = "Date")
  expect_true(is.double(vec_cast(x, x)))
})

# cast: datetimes -----------------------------------------------------------

test_that("safe casts work as expected", {
  datetime_c <- as.POSIXct("1970-02-01", tz = "UTC")
  datetime_l <- as.POSIXlt("1970-02-01", tz = "UTC")

  expect_equal(vec_cast(NULL, datetime_c), NULL)
  expect_equal(vec_cast(datetime_c, datetime_c), datetime_c)
  expect_equal(vec_cast(datetime_l, datetime_c), datetime_c)
  expect_equal(vec_cast(as.Date(datetime_c), datetime_c), datetime_c)

  expect_equal(vec_cast(NULL, datetime_l), NULL)
  expect_equal(vec_cast(datetime_c, datetime_l), datetime_l)
  expect_equal(vec_cast(datetime_l, datetime_l), datetime_l)
  expect_equal(vec_cast(as.Date(datetime_l), datetime_l), datetime_l)
  expect_error(vec_cast(raw(), datetime_l), class = "vctrs_error_incompatible_type")

  missing_c <- new_datetime(NA_real_, tzone = "UTC")
  missing_l <- as.POSIXlt(missing_c)

  expect_equal(vec_cast(missing_c, missing_c), missing_c)
  expect_equal(vec_cast(missing_l, missing_c), missing_c)
  expect_equal(vec_cast(as.Date(missing_c), missing_c), missing_c)

  expect_equal(vec_cast(missing_l, missing_l), missing_l)
  expect_equal(vec_cast(missing_c, missing_l), missing_l)
  expect_equal(vec_cast(as.Date(missing_l), missing_l), missing_l)

  # These used to be allowed
  expect_error(vec_cast(2678400, datetime_c), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast("1970-02-01", datetime_c), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast(list(datetime_c), datetime_c), class = "vctrs_error_incompatible_type")

  expect_error(vec_cast(2678400, datetime_l), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast("1970-02-01", datetime_l), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast(list(datetime_l), datetime_l), class = "vctrs_error_incompatible_type")
})

test_that("invalid casts generate error", {
  datetime <- as.POSIXct("1970-02-01", tz = "UTC")
  expect_error(vec_cast(integer(), datetime), class = "vctrs_error_incompatible_type")
})

test_that("dates become midnight in date-time tzone", {
  date1 <- as.Date("2010-01-01")
  datetime_c <- as.POSIXct(character(), tz = "Pacific/Auckland")
  datetime_l <- as.POSIXlt(character(), tz = "Pacific/Auckland")

  date2_c <- vec_cast(date1, datetime_c)
  expect_equal(tzone(date2_c), "Pacific/Auckland")
  expect_equal(format(date2_c, "%H:%M"), "00:00")

  date2_l <- vec_cast(date1, datetime_l)
  expect_equal(tzone(date2_l), "Pacific/Auckland")
  expect_equal(format(date2_l, "%H:%M"), "00:00")
})

test_that("can cast NA and unspecified to POSIXct and POSIXlt", {
  dtc <- as.POSIXct("2020-01-01")
  dtl <- as.POSIXlt("2020-01-01")
  expect_identical(vec_cast(NA, dtc), vec_init(dtc))
  expect_identical(vec_cast(NA, dtl), vec_init(dtl))
  expect_identical(vec_cast(unspecified(2), dtc), vec_init(dtc, 2))
  expect_identical(vec_cast(unspecified(2), dtl), vec_init(dtl, 2))
})


# cast: durations ------------------------------------------------------------

test_that("safe casts work as expected", {
  dt1 <- as.difftime(600, units = "secs")
  dt2 <- as.difftime(10, units = "mins")

  expect_equal(vec_cast(NULL, dt1), NULL)
  expect_equal(vec_cast(dt1, dt1), dt1)
  expect_equal(vec_cast(dt1, dt2), dt2)

  # These used to be allowed
  expect_error(vec_cast(600, dt1), class = "vctrs_error_incompatible_type")
  expect_error(vec_cast(list(dt1), dt1), class = "vctrs_error_incompatible_type")
})

test_that("invalid casts generate error", {
  dt <- as.difftime(600, units = "secs")
  expect_error(vec_cast(integer(), dt), class = "vctrs_error_incompatible_type")
})

test_that("can cast NA and unspecified to duration", {
  expect_identical(vec_cast(NA, new_duration()), new_duration(na_dbl))
  expect_identical(vec_cast(unspecified(2), new_duration()), new_duration(dbl(NA, NA)))
})


# arithmetic --------------------------------------------------------------

test_that("default is error", {
  d <- as.Date("2018-01-01")
  dt <- as.POSIXct("2018-01-02 12:00")
  t <- as.difftime(12, units = "hours")
  f <- factor("x")

  expect_error(vec_arith("+", d, f), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("+", dt, f), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("+", t, f), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("*", dt, t), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("*", d, t), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("!", t, MISSING()), class = "vctrs_error_incompatible_op")
})

test_that("date-time vs date-time", {
  d <- as.Date("2018-01-01")
  dt <- as.POSIXct(d)

  expect_error(vec_arith("+", d, d), class = "vctrs_error_incompatible_op")
  expect_equal(vec_arith("-", d, d), d - d)

  expect_error(vec_arith("+", d, dt), class = "vctrs_error_incompatible_op")
  expect_equal(vec_arith("-", d, dt), difftime(d, dt))

  expect_error(vec_arith("+", dt, d), class = "vctrs_error_incompatible_op")
  expect_equal(vec_arith("-", dt, d), difftime(dt, d))

  expect_error(vec_arith("+", dt, dt), class = "vctrs_error_incompatible_op")
  expect_equal(vec_arith("-", dt, dt), dt - dt)
})

test_that("date-time vs numeric", {
   d <- as.Date("2018-01-01")
   dt <- as.POSIXct(d)

   expect_equal(vec_arith("+", d, 1), d + 1)
   expect_equal(vec_arith("+", 1, d), d + 1)
   expect_equal(vec_arith("-", d, 1), d - 1)
   expect_error(vec_arith("-", 1, d), class = "vctrs_error_incompatible_op")

   expect_error(vec_arith("*", 1, d), class = "vctrs_error_incompatible_op")
   expect_error(vec_arith("*", d, 1), class = "vctrs_error_incompatible_op")
})

test_that("date-time vs difftime", {
  d <- as.Date("2018-01-01")
  dt <- as.POSIXct(d)
  t <- as.difftime(1, units = "days")
  th <- as.difftime(c(1, 24), units = "hours")

  expect_equal(vec_arith("+", dt, t), dt + t)
  expect_equal(vec_arith("+", d, t), d + t)
  expect_equal(vec_arith("+", dt, th), dt + th)
  expect_lossy(vec_arith("+", d, th), d + th, x = t, to = d)
  expect_equal(vec_arith("-", dt, t), dt - t)
  expect_equal(vec_arith("-", d, t), d - t)
  expect_equal(vec_arith("-", dt, th), dt - th)
  expect_lossy(vec_arith("-", d, th), d - th, x = t, to = d)

  expect_equal(vec_arith("+", t, dt), dt + t)
  expect_equal(vec_arith("+", t, d), d + t)
  expect_equal(vec_arith("+", th, dt), dt + th)
  expect_lossy(vec_arith("+", th, d), d + th, x = t, to = d)

  expect_error(vec_arith("-", t, dt), class = "vctrs_error_incompatible_op")
  expect_error(vec_arith("-", t, d), class = "vctrs_error_incompatible_op")
})

test_that("difftime vs difftime/numeric", {
  t <- as.difftime(12, units = "hours")

  expect_equal(vec_arith("-", t, MISSING()), -t)
  expect_equal(vec_arith("+", t, MISSING()), t)

  expect_equal(vec_arith("-", t, t), t - t)
  expect_equal(vec_arith("-", t, 1), t - 1)
  expect_equal(vec_arith("-", 1, t), 1 - t)

  expect_equal(vec_arith("+", t, t), 2 * t)
  expect_equal(vec_arith("+", t, 1), t + 1)
  expect_equal(vec_arith("+", 1, t), t + 1)

  expect_equal(vec_arith("*", 2, t), 2 * t)
  expect_equal(vec_arith("*", t, 2), 2 * t)
  expect_error(vec_arith("*", t, t), class = "vctrs_error_incompatible_op")

  expect_equal(vec_arith("/", t, 2), t / 2)
  expect_error(vec_arith("/", 2, t), class = "vctrs_error_incompatible_op")

  expect_equal(vec_arith("/", t, t), 1)
  expect_equal(vec_arith("%/%", t, t), 1)
  expect_equal(vec_arith("%%", t, t), 0)
})


# Math --------------------------------------------------------------------

test_that("date and date times don't support math", {
  expect_error(vec_math("sum", new_date()), class = "vctrs_error_unsupported")
  expect_error(vec_math("sum", new_datetime()), class = "vctrs_error_unsupported")
})
