# cython: c_string_type=unicode, c_string_encoding=utf8, language_level=2

# #############################################################################
# Copyright 2018 Hoffmann-La Roche
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# #############################################################################

# TODO:
## if want to profile: # cython: profile=True

import multiprocessing as mp

import pandas as pd

from readstat_api cimport readstat_parse_sas7bdat, readstat_parse_dta, readstat_parse_sav
from readstat_api cimport readstat_parse_por, readstat_parse_xport
from readstat_api cimport readstat_parse_sas7bcat
from readstat_api cimport readstat_begin_writing_dta, readstat_begin_writing_por, readstat_begin_writing_sav
from _readstat_parser cimport py_file_format, run_conversion
from _readstat_writer cimport run_write
cimport _readstat_parser, _readstat_writer
from copy import deepcopy
from worker import worker

# Public interface

# Parsing functions

def read_sas7bdat(filename_path, metadataonly=False, dates_as_pandas_datetime=False, catalog_file=None,
                  formats_as_category=True, formats_as_ordered_category=False, str encoding=None, list usecols=None, user_missing=False,
                  disable_datetime_conversion=False, int row_limit=0, int row_offset=0):
    r"""
    Read a SAS sas7bdat file.
    It accepts the path to a sas7bcat.
    
    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. In python 2.7 the string is assumed to be utf-8 encoded.
        metadataonly : bool, optional
            by default False. IF true, no data will be read but only metadata, so that you can get all elements in the
            metadata object. The data frame will be set with the correct column names but no data.
        dates_as_pandas_datetime : bool, optional
            by default False. If true dates will be transformed to pandas datetime64 instead of date.
        catalog_file : str, optional
            path to a sas7bcat file. By default is None. If not None, will parse the catalog file and replace the values
            by the formats in the catalog, if any appropiate is found. If this is not the behavior you are looking for,
            Use read_sas7bcat to parse the catalog independently
            of the sas7bdat and set_catalog_to_sas to apply the resulting format into sas7bdat files.
        formats_as_category : bool, optional
            Will take effect only if the catalog_file was specified. If True the variables whose values were replaced
            by the formats will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name
        usecols : list, optional
            a list with column names to read from the file. Only those columns will be imported. Case sensitive!
        user_missing : bool, optional
            by default False, in this case user defined missing values are delivered as nan. If true, the missing values
            will be deliver as is, and an extra piece of information will be set in the metadata (missing_user_values)
            to be able to interpret those values as missing.
        disable_datetime_conversion : bool, optional
            if True pyreadstat will not attempt to convert dates, datetimes and times to python objects but those columns
            will remain as numbers. In order to convert them later to an appropiate python object, the user can use the
            information about the original variable format stored in the metadata object in original_variable_types.
            Disabling datetime conversion speeds up reading files. In addition it helps to overcome situations where
            there are datetimes that are beyond the limits of python datetime (which is limited to year 10,000, dates
            beyond that will rise an Overflow error in pyreadstat).
        row_limit : int, optional
            maximum number of rows to read. The default is 0 meaning unlimited.
        row_offset : int, optional
            start reading rows after this offset. By default 0, meaning start with the first row not skipping anything.

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata
            object with metadata. The members variables_value_labels will be empty unless a valid catalog file is
            supplied.
            Look at the documentation for more information.
    """

    cdef bint metaonly = 0
    if metadataonly:
        metaonly = 1

    cdef bint dates_as_pandas = 0
    if dates_as_pandas_datetime:
        dates_as_pandas = 1

    cdef bint usernan = 0
    if user_missing:
        usernan = 1

    cdef bint no_datetime_conversion = 0
    if disable_datetime_conversion:
        no_datetime_conversion = 1
    
    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_SAS
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_sas7bdat, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, <long>row_limit, <long>row_offset)
    metadata.file_format = "sas7bdat"

    if catalog_file:
        _ , catalog = read_sas7bcat(catalog_file, encoding=encoding)
        data_frame, metadata = set_catalog_to_sas(data_frame, metadata, catalog, formats_as_category=formats_as_category, 
                                formats_as_ordered_category=formats_as_ordered_category)

    return data_frame, metadata


def read_xport(filename_path, metadataonly=False, dates_as_pandas_datetime=False, str encoding=None,
               list usecols=None, disable_datetime_conversion=False, int row_limit=0, int row_offset=0):
    r"""
    Read a SAS xport file.

    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. In python 2.7 the string is assumed to be utf-8 encoded
        metadataonly : bool, optional
            by default False. IF true, no data will be read but only metadata, so that you can get all elements in the
            metadata object. The data frame will be set with the correct column names but no data.
        dates_as_pandas_datetime : bool, optional
            by default False. If true dates will be transformed to pandas datetime64 instead of date.
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name
        usecols : list, optional
            a list with column names to read from the file. Only those columns will be imported. Case sensitive!
        disable_datetime_conversion : bool, optional
            if True pyreadstat will not attempt to convert dates, datetimes and times to python objects but those columns
            will remain as numbers. In order to convert them later to an appropiate python object, the user can use the
            information about the original variable format stored in the metadata object in original_variable_types.
            Disabling datetime conversion speeds up reading files. In addition it helps to overcome situations where
            there are datetimes that are beyond the limits of python datetime (which is limited to year 10,000, dates
            beyond that will rise an Overflow error in pyreadstat).
        row_limit : int, optional
            maximum number of rows to read. The default is 0 meaning unlimited.
        row_offset : int, optional
            start reading rows after this offset. By default 0, meaning start with the first row not skipping anything.

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. Look at the documentation for more information.
    """

    cdef bint metaonly = 0
    if metadataonly:
        metaonly = 1

    cdef bint dates_as_pandas = 0
    if dates_as_pandas_datetime:
        dates_as_pandas = 1

    cdef bint usernan = 0

    cdef bint no_datetime_conversion = 0
    if disable_datetime_conversion:
        no_datetime_conversion = 1
    
    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_SAS
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_xport, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, <long>row_limit, <long>row_offset)
    metadata.file_format = "xport"

    return data_frame, metadata


def read_dta(filename_path, metadataonly=False, dates_as_pandas_datetime=False, apply_value_formats=False,
             formats_as_category=True, formats_as_ordered_category=False, str encoding=None, list usecols=None, user_missing=False,
             disable_datetime_conversion=False, int row_limit=0, int row_offset=0):
    r"""
    Read a STATA dta file

    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. In Python 2.7 the string is assumed to be utf-8 encoded
        metadataonly : bool, optional
            by default False. IF true, no data will be read but only metadata, so that you can get all elements in the
            metadata object. The data frame will be set with the correct column names but no data.
        dates_as_pandas_datetime : bool, optional
            by default False. If true dates will be transformed to pandas datetime64 instead of date.
        apply_value_formats : bool, optional
            by default False. If true it will change values in the dataframe for they value labels in the metadata,
            if any appropiate are found.
        formats_as_category : bool, optional
            by default True. Takes effect only if apply_value_formats is True. If True, variables with values changed
            for their formatted version will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name
        usecols : list, optional
            a list with column names to read from the file. Only those columns will be imported. Case sensitive!
        user_missing : bool, optional
            by default False, in this case user defined missing values are delivered as nan. If true, the missing values
            will be deliver as is, and an extra piece of information will be set in the metadata (missing_user_values)
            to be able to interpret those values as missing.
        disable_datetime_conversion : bool, optional
            if True pyreadstat will not attempt to convert dates, datetimes and times to python objects but those columns
            will remain as numbers. In order to convert them later to an appropiate python object, the user can use the
            information about the original variable format stored in the metadata object in original_variable_types.
            Disabling datetime conversion speeds up reading files. In addition it helps to overcome situations where
            there are datetimes that are beyond the limits of python datetime (which is limited to year 10,000, dates
            beyond that will rise an Overflow error in pyreadstat).
        row_limit : int, optional
            maximum number of rows to read. The default is 0 meaning unlimited.
        row_offset : int, optional
            start reading rows after this offset. By default 0, meaning start with the first row not skipping anything.

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. Look at the documentation for more information.
    """

    cdef bint metaonly = 0
    if metadataonly:
        metaonly = 1

    cdef bint dates_as_pandas = 0
    if dates_as_pandas_datetime:
        dates_as_pandas = 1

    cdef bint usernan = 0
    if user_missing:
        usernan = 1

    cdef bint no_datetime_conversion = 0
    if disable_datetime_conversion:
        no_datetime_conversion = 1
    
    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_STATA
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_dta, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, <long>row_limit, <long>row_offset)
    metadata.file_format = "dta"

    if apply_value_formats:
        data_frame = set_value_labels(data_frame, metadata, formats_as_category=formats_as_category,
                                      formats_as_ordered_category=formats_as_ordered_category)

    return data_frame, metadata


def read_sav(filename_path, metadataonly=False, dates_as_pandas_datetime=False, apply_value_formats=False,
             formats_as_category=True, formats_as_ordered_category=False, str encoding=None, list usecols=None, user_missing=False,
             disable_datetime_conversion=False, int row_limit=0, int row_offset=0):
    r"""
    Read a SPSS sav or zsav (compressed) files

    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. In Python 2.7 the string is assumed to be utf-8 encoded
        metadataonly : bool, optional
            by default False. IF true, no data will be read but only metadata, so that you can get all elements in the
            metadata object. The data frame will be set with the correct column names but no data.
        dates_as_pandas_datetime : bool, optional
            by default False. If true dates will be transformed to pandas datetime64 instead of date.
        apply_value_formats : bool, optional
            by default False. If true it will change values in the dataframe for they value labels in the metadata,
            if any appropiate are found.
        formats_as_category : bool, optional
            by default True. Takes effect only if apply_value_formats is True. If True, variables with values changed
            for their formatted version will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name
        usecols : list, optional
            a list with column names to read from the file. Only those columns will be imported. Case sensitive!
        user_missing : bool, optional
            by default False, in this case user defined missing values are delivered as nan. If true, the missing values
            will be deliver as is, and an extra piece of information will be set in the metadata (missing_ranges)
            to be able to interpret those values as missing.
        disable_datetime_conversion : bool, optional
            if True pyreadstat will not attempt to convert dates, datetimes and times to python objects but those columns
            will remain as numbers. In order to convert them later to an appropiate python object, the user can use the
            information about the original variable format stored in the metadata object in original_variable_types.
            Disabling datetime conversion speeds up reading files. In addition it helps to overcome situations where
            there are datetimes that are beyond the limits of python datetime (which is limited to year 10,000, dates
            beyond that will rise an Overflow error in pyreadstat).
        row_limit : int, optional
            maximum number of rows to read. The default is 0 meaning unlimited.
        row_offset : int, optional
            start reading rows after this offset. By default 0, meaning start with the first row not skipping anything.

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. Look at the documentation for more information.
    """

    cdef bint metaonly = 0
    if metadataonly:
        metaonly = 1

    cdef bint dates_as_pandas = 0
    if dates_as_pandas_datetime:
        dates_as_pandas = 1

    cdef bint usernan = 0
    if user_missing:
        usernan = 1

    cdef bint no_datetime_conversion = 0
    if disable_datetime_conversion:
        no_datetime_conversion = 1
    
    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_SPSS
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_sav, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, <long>row_limit, <long>row_offset)
    metadata.file_format = "sav/zsav"

    if apply_value_formats:
        data_frame = set_value_labels(data_frame, metadata, formats_as_category=formats_as_category,
                                      formats_as_ordered_category=formats_as_ordered_category)

    return data_frame, metadata


def read_por(filename_path, metadataonly=False, dates_as_pandas_datetime=False, apply_value_formats=False,
             formats_as_category=True, formats_as_ordered_category=False, str encoding=None, list usecols=None,
             disable_datetime_conversion=False, int row_limit=0, int row_offset=0):
    r"""
    Read a SPSS por file

    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. In Python 2.7 the string is assumed to be utf-8 encoded
        metadataonly : bool, optional
            by default False. IF true, no data will be read but only metadata, so that you can get all elements in the
            metadata object. The data frame will be set with the correct column names but no data.
        dates_as_pandas_datetime : bool, optional
            by default False. If true dates will be transformed to pandas datetime64 instead of date.
        apply_value_formats : bool, optional
            by default False. If true it will change values in the dataframe for they value labels in the metadata,
            if any appropiate are found.
        formats_as_category : bool, optional
            by default True. Takes effect only if apply_value_formats is True. If True, variables with values changed
            for their formatted version will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name
        usecols : list, optional
            a list with column names to read from the file. Only those columns will be imported. Case sensitive!
        disable_datetime_conversion : bool, optional
            if True pyreadstat will not attempt to convert dates, datetimes and times to python objects but those columns
            will remain as numbers. In order to convert them later to an appropiate python object, the user can use the
            information about the original variable format stored in the metadata object in original_variable_types.
            Disabling datetime conversion speeds up reading files. In addition it helps to overcome situations where
            there are datetimes that are beyond the limits of python datetime (which is limited to year 10,000, dates
            beyond that will rise an Overflow error in pyreadstat).
        row_limit : int, optional
            maximum number of rows to read. The default is 0 meaning unlimited.
        row_offset : int, optional
            start reading rows after this offset. By default 0, meaning start with the first row not skipping anything.

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. Look at the documentation for more information.
    """

    cdef bint metaonly = 0
    if metadataonly:
        metaonly = 1

    cdef bint dates_as_pandas = 0
    if dates_as_pandas_datetime:
        dates_as_pandas = 1

    cdef bint usernan = 0

    cdef bint no_datetime_conversion = 0
    if disable_datetime_conversion:
        no_datetime_conversion = 1
    
    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_SPSS
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_por, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, <long>row_limit, <long>row_offset)
    metadata.file_format = "por"
    if apply_value_formats:
        data_frame = set_value_labels(data_frame, metadata, formats_as_category=formats_as_category)

    return data_frame, metadata
    


def read_sas7bcat(filename_path, str encoding=None):
    r"""
    Read a SAS sas7bcat file. The returning dataframe will be empty. The metadata object will contain a dictionary
    value_labels that contains the formats. When parsing the sas7bdat file, in the metadata, the dictionary
    variable_to_label contains a map from variable name to the formats.
    In order to apply the catalog to the sas7bdat file use set_catalog_to_sas or pass the catalog file as an argument
    to read_sas7bdat directly.
    SAS catalog files are difficult ones, some of them can be read only in specific SAS version, may contain strange
    encodings etc. Therefore it may be that many catalog files are not readable from this application.

    Parameters
    ----------
        filename_path : str, bytes or Path-like object
            path to the file. The string is assumed to be utf-8 encoded
        encoding : str, optional
            Defaults to None. If set, the system will use the defined encoding instead of guessing it. It has to be an
            iconv-compatible name

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data (no data in this case, so will be empty)
        metadata :
            object with metadata. The member value_labels is the one that contains the formats.
            Look at the documentation for more information.
    """
    cdef bint metaonly = 1
    cdef bint dates_as_pandas = 0
    cdef list usecols = None
    cdef bint usernan = 0
    cdef bint no_datetime_conversion = 0
    cdef long row_limit=0
    cdef long row_offset=0

    cdef py_file_format file_format = _readstat_parser.FILE_FORMAT_SAS
    data_frame, metadata = run_conversion(filename_path, file_format, readstat_parse_sas7bcat, encoding, metaonly,
                                          dates_as_pandas, usecols, usernan, no_datetime_conversion, row_limit, row_offset)
    metadata.file_format = "sas7bcat"

    return data_frame, metadata

# Functions to deal with value labels


def set_value_labels(dataframe, metadata, formats_as_category=True, formats_as_ordered_category=False):
    """
    Changes the values in the dataframe according to the value formats in the metadata.
    It will return a copy of the dataframe. If no appropiate formats were found, the result will be an unchanged copy
    of the original dataframe.

    Parameters
    ----------
        dataframe : pandas dataframe
            resulting from parsing a file
        metadata : dictionary
            resulting from parsing a file
        formats_as_category : bool, optional
            defaults to True. If True the variables having formats will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.

    Returns
    -------
        df_copy : pandas dataframe
            a copy of the original dataframe with the values changed, if appropiate formats were found, unaltered
            otherwise
    """

    df_copy = dataframe.copy()

    if metadata.value_labels and metadata.variable_to_label:
        for var_name, label_name in metadata.variable_to_label.items():
            labels = metadata.value_labels.get(label_name)
            if labels:
                if var_name in df_copy.columns:
                    df_copy[var_name] = df_copy[var_name].apply(lambda x: labels.get(x, x))
                    if formats_as_ordered_category:
                        categories = list(set(labels.values()))
                        original_values = list(labels.keys())
                        original_values.sort()
                        revdict= dict()
                        for orival in original_values:
                            curcat = labels.get(orival)
                            if not revdict.get(curcat):
                                revdict[curcat] = orival
                        categories.sort(key=revdict.get)
                        df_copy[var_name] = pd.Categorical(
                            df_copy[var_name],
                            ordered = True,
                            categories = categories
                        )
                    elif formats_as_category:
                        df_copy[var_name] = df_copy[var_name].astype("category")


    return df_copy

def set_catalog_to_sas(sas_dataframe, sas_metadata, catalog_metadata, formats_as_category=True,  
                       formats_as_ordered_category=False):
    """
    Changes the values in the dataframe and sas_metadata according to the formats in the catalog.
    It will return a copy of the dataframe and metadata. If no appropriate formats were found, the result will
    be an unchanged copy of the original dataframe.

    Parameters
    ----------
        sas_dataframe : pandas dataframe
            resulting from parsing a sas7bdat file
        sas_metadata : pyreadstat metadata object
            resulting from parsing a sas7bdat file
        catalog_metadata : pyreadstat metadata object
            resulting from parsing a sas7bcat (catalog) file
        formats_as_category : bool, optional
            defaults to True. If True the variables having formats will be transformed into pandas categories.
        formats_as_ordered_category : bool, optional
            defaults to False. If True the variables having formats will be transformed into pandas ordered categories.
            it has precedence over formats_as_category, meaning if this is True, it will take effect irrespective of
            the value of formats_as_category.

    Returns
    -------
        df_copy : pandas dataframe
            a copy of the original dataframe with the values changed, if appropriate formats were found, unaltered
            otherwise
        metadata : dict
            a copy of the original sas_metadata enriched with catalog information if found, otherwise unaltered
    """

    if catalog_metadata.value_labels and sas_metadata.variable_to_label:
        catalog_metadata_copy = deepcopy(catalog_metadata)
        metadata = deepcopy(sas_metadata)
        metadata.value_labels = catalog_metadata_copy.value_labels
        df_copy = set_value_labels(sas_dataframe, metadata, formats_as_category=formats_as_category,
                                   formats_as_ordered_category=formats_as_ordered_category)

        variable_value_labels = dict()
        for var_name, var_label in metadata.variable_to_label.items():
            current_labels = catalog_metadata_copy.value_labels.get(var_label)
            if current_labels:
                variable_value_labels[var_name] = current_labels
        metadata.variable_value_labels = variable_value_labels

    else:
        df_copy = sas_dataframe.copy()
        metadata = deepcopy(sas_metadata)

    return df_copy, metadata

# convenience functions to read in chunks

def read_file_in_chunks(read_function, file_path, chunksize=100000, offset=0, limit=0,
                        multiprocess=False, num_processes=4, **kwargs):
    """
    Returns a generator that will allow to read a file in chunks.

    Parameters
    ----------
        read_function : pyreadstat function
            a pyreadstat reading function
        file_path : string
            path to the file to be read
        chunksize : integer, optional
            size of the chunks to read
        offset : integer, optional
            start reading the file after certain number of rows
        limit : integer, optional
            stop reading the file after certain number of rows, will be added to offset
        multiprocess: bool, optional
            use multiprocessing to read each chunk?
        num_processes: integer, optional
            in case multiprocess is true, how many workers/processes to spawn?
        kwargs : dict, optional
            any other keyword argument to pass to the read_function. row_limit and row_offset will be discarded if present.

    Yields
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. 
            Look at the documentation for more information.

        it : generator
            A generator that reads the file in chunks.
    """

    if read_function == read_sas7bcat:
        raise Exception("read_sas7bcat not supported")
    
    if "row_offset" in kwargs:
        _ = kwargs.pop("row_offset")

    if "row_limit" in kwargs:
        _ = kwargs.pop("row_limit")

    if "num_processes" in kwargs:
        _ = kwargs.pop("num_processes")

    _, meta = read_function(file_path, metadataonly=True)
    numrows = meta.number_rows
    if numrows:
        if not limit:
            limit = numrows
        else:
            limit = min(offset+limit, numrows)
    else:
        if limit:
            limit = offset + limit
    df = [0]
    while len(df):
        if limit and (offset >= limit):
            break
        if multiprocess:
            df, meta = read_file_multiprocessing(read_function, file_path, num_processes=num_processes,
                                                 row_offset=offset, row_limit=chunksize, **kwargs)
        else:
            df, meta = read_function(file_path, row_offset=offset, row_limit=chunksize, **kwargs)
        if len(df):
            yield df, meta
            offset += chunksize

def read_file_multiprocessing(read_function, file_path, num_processes=None, **kwargs):
    """
    Reads a file in parallel using multiprocessing.

    Parameters
    ----------
        read_function : pyreadstat function
            a pyreadstat reading function
        file_path : string
            path to the file to be read
        num_processes : integer, optional
            number of processes to spawn, by default the min 4 and the max cores on the computer
        kwargs : dict, optional
            any other keyword argument to pass to the read_function. 

    Returns
    -------
        data_frame : pandas dataframe
            a pandas data frame with the data
        metadata :
            object with metadata. Look at the documentation for more information.
    """

    if read_function in (read_sas7bcat, read_xport, read_por):
        raise Exception("read_sas7bcat, read_xport and read_por are not supported")

    if not num_processes:
        # let's be more conservative with the number of workers
        num_processes = min(mp.cpu_count(), 4)
    _ = kwargs.pop('metadataonly', None)
    row_offset = kwargs.pop("row_offset", 0)
    row_limit = kwargs.pop("row_limit", float('inf'))
    _, meta = read_function(file_path, metadataonly=True, **kwargs)
    numrows = meta.number_rows
    if not numrows:
        raise Exception("The number of rows of the file cannot be determined from the file's metadata")
    numrows = min(max(numrows - row_offset, 0), row_limit)        
    divs = [numrows // num_processes + (1 if x < numrows % num_processes else 0)  for x in range (num_processes)]
    offsets = list()
    prev_offset = row_offset
    prev_div = 0
    for indx, div in enumerate(divs):
        offset = prev_offset + prev_div
        prev_offset = offset
        prev_div = div
        offsets.append((offset, div))
    jobs = [(read_function, file_path, offset, chunksize, kwargs) for offset, chunksize in offsets]
    pool = mp.Pool(processes=num_processes)
    try:
        chunks = pool.map(worker, jobs)
    except:
        raise
    finally:
        pool.close()
    final = pd.concat(chunks, axis=0, ignore_index=True)
    return final, meta


# Write API

def write_sav(df, dst_path, str file_label="", object column_labels=None, compress=False, str note=None,
                dict variable_value_labels=None, dict missing_ranges=None, dict variable_display_width=None,
                dict variable_measure=None, dict variable_format=None):
    """
    Writes a pandas data frame to a SPSS sav or zsav file.

    Parameters
    ----------
    df : pandas data frame
        pandas data frame to write to sav or zsav
    dst_path : str or pathlib.Path
        full path to the result sav or zsav file
    file_label : str, optional
        a label for the file
    column_labels : list or dict, optional
        labels for columns (variables), if list must be the same length as the number of columns. Variables with no
        labels must be represented by None. If dict values must be variable names and values variable labels.
        In such case there is no need to include all variables; labels for non existent
        variables will be ignored with no warning or error.
    compress : boolean, optional
        if true a zsav will be written, by default False, a sav is written
    note : str, optional
        a note to add to the file
    variable_value_labels : dict, optional
        value labels, a dictionary with key variable name and value a dictionary with key values and
        values labels. Variable names must match variable names in the dataframe otherwise will be
        ignored. Value types must match the type of the column in the dataframe.
    missing_ranges : dict, optional
        user defined missing values. Must be a dictionary with keys as variable names matching variable
        names in the dataframe. The values must be a list. Each element in that list can either be
        either a discrete numeric or string value (max 3 per variable) or a dictionary with keys 'hi' and 'lo' to
        indicate the upper and lower range for numeric values (max 1 range value + 1 discrete value per
        variable). hi and lo may also be the same value in which case it will be interpreted as a discrete
        missing value.
        For this to be effective, values in the dataframe must be the same as reported here and not NaN.
    variable_display_width : dict, optional
        set the display width for variables. Must be a dictonary with keys being variable names and
        values being integers.
    variable_measure: dict, optional
        sets the measure type for a variable. Must be a dictionary with keys being variable names and
        values being strings one of "nominal", "ordinal", "scale" or "unknown" (default).
    variable_format: dict, optional
        sets the format of a variable. Must be a dictionary with keys being the variable names and 
        values being strings defining the format. See README, setting variable formats section,
        for more information.
    """

    cdef int file_format_version = 2
    cdef str var_width
    if compress:
        file_format_version = 3
    cdef table_name = ""
    cdef dict missing_user_values = None
    cdef dict variable_alignment = None

    # formats
    formats_presets = {'restricted_integer':'N{var_width}', 'integer':'F{var_width}.0'}
    if variable_format:
        for col_name, col_format in variable_format.items():
            if col_format in formats_presets.keys() and col_name in df.columns:
                var_width = str(len(str(max(df[col_name]))))
                variable_format[col_name] = formats_presets[col_format].format(var_width=var_width) 
    
    run_write(df, dst_path, _readstat_writer.FILE_FORMAT_SAV, file_label, column_labels, 
        file_format_version, note, table_name, variable_value_labels, missing_ranges, missing_user_values,
        variable_alignment, variable_display_width, variable_measure, variable_format)

def write_dta(df, dst_path, str file_label="", object column_labels=None, int version=15, 
            dict variable_value_labels=None, dict missing_user_values=None, dict variable_format=None):
    """
    Writes a pandas data frame to a STATA dta file

    Parameters
    ----------
    df : pandas data frame
        pandas data frame to write to sav or zsav
    dst_path : str or pathlib.Path
        full path to the result sav or zsav file
    file_label : str, optional
        a label for the file
    column_labels : list or dict, optional
        labels for columns (variables), if list must be the same length as the number of columns. Variables with no
        labels must be represented by None. If dict values must be variable names and values variable labels.
        In such case there is no need to include all variables; labels for non existent
        variables will be ignored with no warning or error.
    version : int, optional
        dta file version, supported from 8 to 15, default is 15
    variable_value_labels : dict, optional
        value labels, a dictionary with key variable name and value a dictionary with key values and
        values labels. Variable names must match variable names in the dataframe otherwise will be
        ignored. Value types must match the type of the column in the dataframe.
    missing_user_values : dict, optional
        user defined missing values for numeric variables. Must be a dictionary with keys being variable
        names and values being a list of missing values. Missing values must be a single character
        between a and z.
    variable_format: dict, optional
        sets the format of a variable. Must be a dictionary with keys being the variable names and 
        values being strings defining the format. See README, setting variable formats section,
        for more information.
    """

    if version == 15:
        file_format_version = 119
    elif version == 14:
        file_format_version = 118
    elif version == 13:
        file_format_version = 117
    elif version == 12:
        file_format_version = 115
    elif version in {10, 11}:
        file_format_version = 114
    elif version in {8, 9}:
        file_format_version = 113
    else:
        raise Exception("Version not supported")

    cdef str note = ""
    cdef str table_name = ""
    cdef dict missing_ranges = None
    cdef dict variable_alignment = None
    cdef dict variable_display_width = None
    cdef dict variable_measure = None
    #cdef dict variable_format = None

    run_write(df, dst_path, _readstat_writer.FILE_FORMAT_DTA, file_label, column_labels, file_format_version,
     note, table_name, variable_value_labels, missing_ranges, missing_user_values, variable_alignment,
     variable_display_width, variable_measure, variable_format)

def write_xport(df, dst_path, str file_label="", object column_labels=None, str table_name=None, int file_format_version = 8,
    dict variable_format=None):
    """
    Writes a pandas data frame to a SAS Xport (xpt) file.
    If no table_name is specified the dataset has by default the name DATASET (take it into account if
    reading the file from SAS.)
    Versions 5 and 8 are supported, default is 8.

    Parameters
    ----------
    df : pandas data frame
        pandas data frame to write to sav or zsav
    dst_path : str or pathlib.Path
        full path to the result sav or zsav file
    file_label : str, optional
        a label for the file
    column_labels : list or dict, optional
        labels for columns (variables), if list must be the same length as the number of columns. Variables with no
        labels must be represented by None. If dict values must be variable names and values variable labels.
        In such case there is no need to include all variables; labels for non existent
        variables will be ignored with no warning or error.
    table_name : str, optional
        name of the dataset, by default DATASET
    file_format_version : int, optional
        XPORT file version, either 8 or 5, default is 8
    variable_format: dict, optional
        sets the format of a variable. Must be a dictionary with keys being the variable names and 
        values being strings defining the format. See README, setting variable formats section,
        for more information.
    """

    cdef dict variable_value_labels = None
    cdef str note = ""
    cdef dict missing_ranges = None
    cdef dict missing_user_values = None
    cdef dict variable_alignment = None
    cdef dict variable_display_width = None
    cdef dict variable_measure = None
    #cdef dict variable_format = None
    run_write(df, dst_path, _readstat_writer.FILE_FORMAT_XPORT, file_label, column_labels, 
        file_format_version, note, table_name, variable_value_labels, missing_ranges,missing_user_values,
        variable_alignment,variable_display_width, variable_measure, variable_format)

def write_por(df, dst_path, str file_label="", object column_labels=None, dict variable_format=None):
    """
    Writes a pandas data frame to a SPSS POR file.

    Parameters
    ----------
    df : pandas data frame
        pandas data frame to write to sav or zsav
    dst_path : str or pathlib.Path
        full path to the result sav or zsav file
    file_label : str, optional
        a label for the file
    column_labels : list or dict, optional
        labels for columns (variables), if list must be the same length as the number of columns. Variables with no
        labels must be represented by None. If dict values must be variable names and values variable labels.
        In such case there is no need to include all variables; labels for non existent
        variables will be ignored with no warning or error.
    variable_format: dict, optional
        sets the format of a variable. Must be a dictionary with keys being the variable names and 
        values being strings defining the format. See README, setting variable formats section,
        for more information.
    """

    # atm version 5 and 8 are supported by readstat but only 5 can be later be read by SAS
    cdef str note=None
    cdef int file_format_version = 0
    cdef dict variable_value_labels=None
    cdef dict missing_ranges = None
    cdef dict missing_user_values = None
    cdef dict variable_alignment = None
    cdef dict variable_display_width = None
    cdef dict variable_measure = None
    cdef str table_name = ""
    #cdef dict variable_format = None
    run_write(df, dst_path, _readstat_writer.FILE_FORMAT_POR, file_label, column_labels,
        file_format_version, note, table_name, variable_value_labels, missing_ranges,missing_user_values,
        variable_alignment,variable_display_width, variable_measure, variable_format)
