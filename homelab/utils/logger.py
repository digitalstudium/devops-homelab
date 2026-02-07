import sys

from . import colors


# Logging functions
def info(msg: str):
    print(f"{colors.BLUE}[INFO]{colors.RESET} {msg}")


def ok(msg: str):
    print(f"{colors.GREEN}[OK]{colors.RESET} {msg}")


def warn(msg: str):
    print(f"{colors.YELLOW}[WARN]{colors.RESET} {msg}")


def error(msg: str):
    print(f"{colors.RED}[ERROR]{colors.RESET} {msg}")


def step(msg: str):
    print(f"\n{colors.CYAN}{colors.BOLD}--- {msg} ---{colors.RESET}")


def die(msg: str):
    error(msg)
    sys.exit(1)
