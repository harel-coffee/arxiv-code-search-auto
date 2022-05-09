"""
Combine multiple csv or ods files, that contain labels, into one. Save into the data/processed/labels/labels_complete directory.
"""

from pathlib import Path
import pandas as pd
from multiprocessing import Pool
import os
import logging
import argparse

def read_csv(filename):
    'converts a filename to a pandas dataframe'
    return pd.read_csv(filename)


def main(folder_interim_data):
    """Runs data processing scripts to turn raw data from (../raw) into
    cleaned data ready to be analyzed (saved in ../processed).
    """
    logger = logging.getLogger(__name__)
    logger.info("making final data set from raw data")

    # get a list of file names
    files = os.listdir(folder_interim_data)
    file_list = [
        Path(folder_interim_data) / filename
        for filename in files
        if filename.endswith(".csv")
    ]

    # set up your pool
    with Pool(processes=num_pool_processes) as pool:  # or whatever your hardware can support

        # have your pool map the file names to dataframes
        df_list = pool.map(read_csv, file_list)

        # reduce the list of dataframes to a single dataframe
        combined_df = pd.concat(df_list, ignore_index=True)

        return combined_df


if __name__ == "__main__":
    logger = logging.getLogger(__name__)
    logger.info("combine multiple label csv or ods files into one")

    parser = argparse.ArgumentParser(description="Create final labels.")

    parser.add_argument(
        "--path_data_folder",
        type=str,
        default="data/",
        help="Path to data folder that contains raw/interim/processed data folders",
    )

    parser.add_argument(
        "--num_pool_processes",
        type=int,
        default=2,
        help="Number of processes to use for multiprocessing",
    )

    args = parser.parse_args()

    path_data_folder = Path(args.path_data_folder)
    num_pool_processes = int(args.num_pool_processes)


    ### Milling data ###
    folder_raw_data_milling = path_data_folder / "raw/milling"
    folder_interim_data_milling = path_data_folder / "interim/milling"
    folder_processed_data_milling = path_data_folder / "processed/milling"

    df = main(folder_interim_data_milling)
    print("Final df shape:", df.shape)

    df.to_csv(folder_processed_data_milling / "milling_features.csv.gz", compression="gzip", index=False)