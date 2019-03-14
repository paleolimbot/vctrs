#include "vctrs.h"
#include "utils.h"

// Initialised at load time
SEXP vec_slice_dispatch_fn = NULL;

// Defined below
SEXP vec_as_index(SEXP i, SEXP x);
static void slice_copy_attributes(SEXP to, SEXP from, SEXP index);


static void stop_bad_index_length(R_len_t data_n, R_len_t i) {
  Rf_errorcall(R_NilValue,
               "Can't index beyond the end of a vector.\n"
               "The vector has length %d and you've tried to subset element %d.",
               data_n, i);
}

#define SLICE(RTYPE, CTYPE, DEREF, CONST_DEREF, NA_VALUE)       \
  const CTYPE* data = CONST_DEREF(x);                           \
  R_len_t data_n = Rf_length(x);                                \
                                                                \
  R_len_t n = Rf_length(index);                                 \
  int* index_data = INTEGER(index);                             \
                                                                \
  SEXP out = PROTECT(Rf_allocVector(RTYPE, n));                 \
  CTYPE* out_data = DEREF(out);                                 \
                                                                \
  for (R_len_t i = 0; i < n; ++i, ++index_data, ++out_data) {   \
    int j = *index_data;                                        \
                                                                \
    if (j > data_n) {                                           \
      stop_bad_index_length(data_n, j);                         \
    }                                                           \
                                                                \
    *out_data = (j == NA_INTEGER) ? NA_VALUE : data[j - 1];     \
  }                                                             \
                                                                \
  UNPROTECT(1);                                                 \
  return out

static SEXP lgl_slice(SEXP x, SEXP index) {
  SLICE(LGLSXP, int, LOGICAL, LOGICAL_RO, NA_LOGICAL);
}
static SEXP int_slice(SEXP x, SEXP index) {
  SLICE(INTSXP, int, INTEGER, INTEGER_RO, NA_INTEGER);
}
static SEXP dbl_slice(SEXP x, SEXP index) {
  SLICE(REALSXP, double, REAL, REAL_RO, NA_REAL);
}
static SEXP cpl_slice(SEXP x, SEXP index) {
  SLICE(CPLXSXP, Rcomplex, COMPLEX, COMPLEX_RO, vctrs_shared_na_cpl);
}
static SEXP chr_slice(SEXP x, SEXP index) {
  SLICE(STRSXP, SEXP, STRING_PTR, STRING_PTR_RO, NA_STRING);
}
static SEXP raw_slice(SEXP x, SEXP index) {
  SLICE(RAWSXP, Rbyte, RAW, RAW_RO, 0);
}

#undef SLICE


#define SLICE_BARRIER(RTYPE, GET, SET, NA_VALUE)                \
  R_len_t data_n = Rf_length(x);                                \
                                                                \
  R_len_t n = Rf_length(index);                                 \
  int* index_data = INTEGER(index);                             \
                                                                \
  SEXP out = PROTECT(Rf_allocVector(RTYPE, n));                 \
                                                                \
  for (R_len_t i = 0; i < n; ++i, ++index_data) {               \
    int j = *index_data;                                        \
                                                                \
    if (j > data_n) {                                           \
      stop_bad_index_length(data_n, j);                         \
    }                                                           \
                                                                \
    SEXP elt = (j == NA_INTEGER) ? NA_VALUE : GET(x, j - 1);    \
    SET(out, i, elt);                                           \
  }                                                             \
                                                                \
  UNPROTECT(1);                                                 \
  return out

static SEXP list_slice(SEXP x, SEXP index) {
  SLICE_BARRIER(VECSXP, VECTOR_ELT, SET_VECTOR_ELT, R_NilValue);
}

#undef SLICE_BARRIER


SEXP vctrs_slice(SEXP x, SEXP index) {
  index = PROTECT(vec_as_index(index, x));

  if (index == R_MissingArg) {
    UNPROTECT(1);
    return x;
  }
  if (has_dim(x)) {
    goto dispatch;
  }

  SEXP out = NULL;

  switch (vec_typeof(x)) {
  case vctrs_type_null:
    out = R_NilValue;
    break;

  case vctrs_type_logical: {
    out = lgl_slice(x, index);
    break;
  }
  case vctrs_type_integer: {
    out = int_slice(x, index);
    break;
  }
  case vctrs_type_double: {
    out = dbl_slice(x, index);
    break;
  }
  case vctrs_type_complex: {
    out = cpl_slice(x, index);
    break;
  }
  case vctrs_type_character: {
    out = chr_slice(x, index);
    break;
  }
  case vctrs_type_raw: {
    out = raw_slice(x, index);
    break;
  }
  case vctrs_type_list: {
    out = list_slice(x, index);
    break;
  }

  default:
  dispatch: {
    SEXP dispatch_call = PROTECT(Rf_lang3(vec_slice_dispatch_fn, x, index));
    SEXP out = Rf_eval(dispatch_call, R_GlobalEnv);

    UNPROTECT(2);
    return out;
  }}

  // TODO: Should be the default `vec_restore()` method
  slice_copy_attributes(out, x, index);

  UNPROTECT(1);
  return out;
}

static void slice_copy_attributes(SEXP to, SEXP from, SEXP index) {
  SEXP attrib = PROTECT(Rf_shallow_duplicate(ATTRIB(from)));

  for (SEXP node = attrib; node != R_NilValue; node = CDR(node)) {
    if (TAG(node) != R_NamesSymbol) {
      continue;
    }

    SEXP nms = CAR(node);
    switch (TYPEOF(nms)) {
    case NILSXP:
      break;
    case STRSXP:
      nms = PROTECT(chr_slice(nms, index));
      SETCAR(node, nms);
      UNPROTECT(1);
      break;
    default:
      Rf_error("Internal error: Expected character names in `vec_slice()`.");
    }
  }

  SET_ATTRIB(to, attrib);
  UNPROTECT(1);
}


static SEXP int_as_index(SEXP i, SEXP x) {
  if (Rf_length(i) == 1 && *INTEGER(i) == 0) {
    return vctrs_shared_empty_int;
  } else {
    return i;
  }
}

static SEXP lgl_as_index(SEXP i, SEXP x) {
  R_len_t n = Rf_length(i);

  if (n == Rf_length(x)) {
    return r_lgl_which(i, true);
  }

  // A single `TRUE` or `FALSE` index is recycled to the full vector
  // size. This means `TRUE` is synonym for missing index (i.e. no
  // subsetting) and `FALSE` is synonym for empty index. Returning
  // these sentinels avoids materialising a full index vector.
  if (n == 1) {
    int elt = *LOGICAL(i);
    if (elt == NA_LOGICAL) {
      SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
      r_int_fill(out, NA_INTEGER);
      UNPROTECT(1);
      return out;
    } else if (elt) {
      return R_MissingArg;
    } else {
      return vctrs_shared_empty_int;
    }
  }

  Rf_errorcall(R_NilValue,
               "Logical indices must have length 1 or be as long as the indexed vector.\n"
               "The vector has length %d whereas the index has length %d.",
               n, Rf_length(x));
}

static SEXP chr_as_index(SEXP i, SEXP x) {
  SEXP nms = Rf_getAttrib(x, R_NamesSymbol);

  if (nms == R_NilValue) {
    Rf_errorcall(R_NilValue, "Can't use character to index an unnamed vector.");
  }

  i = PROTECT(Rf_match(nms, i, NA_INTEGER));

  if (r_int_any_na(i)) {
    Rf_errorcall(R_NilValue, "Can't index non-existing elements.");
  }

  UNPROTECT(1);
  return i;
}

SEXP vec_as_index(SEXP i, SEXP x) {
  switch (TYPEOF(i)) {
  case INTSXP: return int_as_index(i, x);
  case LGLSXP: return lgl_as_index(i, x);
  case STRSXP: return chr_as_index(i, x);
  case SYMSXP: if (i == R_MissingArg) return i;

  // Do we really want to forbid numeric indices here (> 2^31)?
  default: Rf_errorcall(R_NilValue, "`i` must be an integer, not a %s.",
                        Rf_type2char(TYPEOF(i)));
  }
}


void vctrs_init_size(SEXP ns) {
  vec_slice_dispatch_fn = Rf_findVar(Rf_install("vec_slice_dispatch"), ns);
}
