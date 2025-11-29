import csv
from typing import List
from utils import URL, fetch_data, lightly_parse_data, SFAddress


def save_to_csv(data: List[SFAddress], filename: str):
    """
    Save the data to a CSV file.

    Args:
        data (list): The data to save.
        filename (str): The name of the CSV file.
    """
    with open(filename, mode="w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(SFAddress.__annotations__.keys())
        for address in data:
            writer.writerow(address.__dict__.values())


if __name__ == "__main__":
    data = fetch_data(URL)
    address_data = lightly_parse_data(data)
    save_to_csv(address_data, "output.csv")