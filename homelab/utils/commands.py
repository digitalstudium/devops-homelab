import subprocess

from . import logger


def run(
    cmd: list[str], check: bool = True, verbose: bool = False, **kwargs
) -> subprocess.CompletedProcess:
    """Run a command and return the result."""
    try:
        result = subprocess.run(
            cmd, check=check, capture_output=True, text=True, **kwargs
        )
        if verbose:
            logger.info(f"$ {' '.join(cmd)}")
            if result.stdout.strip():
                logger.info(result.stdout.strip())
        return result
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {' '.join(e.cmd)}")
        if e.stdout and e.stdout.strip():
            logger.error(f"stdout: {e.stdout.strip()}")
        if e.stderr and e.stderr.strip():
            logger.error(f"stderr: {e.stderr.strip()}")
        if check:
            raise
        return e
