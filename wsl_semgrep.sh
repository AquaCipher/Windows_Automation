#!/bin/bash

# Configuration Section
# ---------------------
# This section defines configuration variables used throughout the script.
# Update these variables according to your environment and requirements.

REPO_URL="https://example.com/tfs/ExampleRepo/_git/ExampleProject"  # Repository URL (TFS / SVN / Git)
GIT_USER_NAME="your_username"  # Git global user name
GIT_USER_EMAIL="your_email@example.com" # Git global user email
REPO_PATH="/home/your_username/ExampleProject/Semgrep"  # Local path to clone the repository
LOG_FILE="/home/your_username/semgrep_cron.log"  # Path to store log file
CRON_SCHEDULE="15 12 * * *" # Cron Schedule (Minute Hour Day Month Weekday)

# Function Definitions
# --------------------

# Function: install_git
# Purpose: Install Git if not already installed and configure global user settings.
install_git() {
    echo "Checking if git installed..."
    # Check if git is installed using command -v
    if ! command -v git &> /dev/null; then
        # Update package list and install Git
        sudo apt update || { echo "Failed to update package list"; exit 1; }
        sudo apt install -y git || { echo "Failed to install git"; exit 1; }
        echo "Git installed"
    else
        echo "Git is already installed"
    fi

    # Configure Git global user.name if not set
    if [ -z "$(git config --global user.name)" ]; then
        git config --global user.name "$GIT_USER_NAME"
        echo "Git global user.name set to $GIT_USER_NAME"
    else
        echo "Git global user.name is already set to $(git config --global user.name)"
    fi

    # Configure Git global user.email if not set
    if [ -z "$(git config --global user.email)" ]; then
        git config --global user.email "$GIT_USER_EMAIL"
        echo "Git global user.email set to $GIT_USER_EMAIL"
    else
        echo "Git global user.email is already set to $(git config --global user.email)"
    fi
}

# Function: clone_repo
# Purpose: Clone a targeted SVN/TFVC/Git repository to a local directory.
clone_repo() {
    echo "Cloning repository..."

    # Create the local directory path if it does not exist
    if [ ! -d "$REPO_PATH" ]; then
        echo "Creating directory path for repository: $REPO_PATH"
        sudo mkdir -p "$REPO_PATH"
    fi

    # Determine repository type and clone accordingly
    # Check if SVN repository
    if [[ $REPO_URL == *"svn"* ]]; then
        echo "SVN repository detected..."
        sudo apt install -y git-svn
        git svn clone $REPO_URL $REPO_PATH
        echo "SVN repository cloned to $REPO_PATH"
    # Check if TFVC repository
    elif [[ $REPO_URL == *"tfs"* && $REPO_URL != *"_git"* ]]; then
        echo "TFVC repository detected..."
        sudo apt update
        sudo apt install -y openjdk-21-jdk unzip

        # Define the local path for git-tf installation
        LOCAL_GIT_TF_PATH="/usr/local/bin/git-tf-2.0.3"

        # Install git-tf if not already installed
        if [ ! -d "$LOCAL_GIT_TF_PATH" ]; then
            # Copy and extract git-tf ZIP file
            unzip git-tf-2.0.3.20131219.zip -d git-tf
            sudo mkdir -p "$LOCAL_GIT_TF_PATH"
            sudo mv git-tf/* "$LOCAL_GIT_TF_PATH/"

            # Modify the git-tf script to set the correct BASE_DIRECTORY
            GIT_TF_SCRIPT="$LOCAL_GIT_TF_PATH/git-tf-2.0.3.20131219/git-tf"
            sudo sed -i "s|BASE_DIRECTORY=.*|BASE_DIRECTORY=\"$LOCAL_GIT_TF_PATH/git-tf-2.0.3.20131219\"|" "$GIT_TF_SCRIPT"

            # Create a symbolic link for git-tf and make executable
            sudo ln -sf "$GIT_TF_SCRIPT" /usr/local/bin/git-tf
            sudo chmod +x "$GIT_TF_SCRIPT"
        fi

        # Extract the TFVC server URL and repository path
        TFVC_SERVER_URL="https://example.com/tfs/ExampleRepo"
        TFVC_REPO_PATH=$(extract_tfvc_repo_path "$REPO_URL")

        # Change to the target directory and clone TFVC repository
        cd "$REPO_PATH" || { echo "Error: Failed to change to directory $REPO_PATH"; return 1; }

        # Clone the TFVC repository using git-tf
        git-tf clone $TFVC_SERVER_URL $TFVC_REPO_PATH . || { echo "Error: Failed to clone TFVC repository"; return 1; }
        echo "TFVC repository cloned to $REPO_PATH"

        # Configure git repository
        echo "Marking $REPO_PATH as a safe directory..."
        git config --global --add safe.directory "$REPO_PATH"
        git remote add origin https://example.com/dummy-repo.git

        # Persist the SEMGREP_REPO_URL environment variable
        echo "export SEMGREP_REPO_URL=https://example.com/dummy-repo.git" >> "$HOME/.bashrc"

    else
        echo "Git repository detected..."
        sudo git clone $REPO_URL $REPO_PATH || { echo "Error: Failed to clone Git repository"; return 1; }
        echo "Git repository cloned to $REPO_PATH"
        echo "Marking $REPO_PATH as a safe directory..."
        git config --global --add safe.directory "$REPO_PATH"
    fi
}

# Function: create_yml_file
# Purpose: Create a YAML configuration file for Semgrep based on user input.
create_yml_file() {
    echo "Creating YML file..."
    YML_FILE="$REPO_PATH/.semgrepconfig.yml"

    # Check if the YAML file already exists
    if [ -f "$YML_FILE" ]; then
        echo "The file $YML_FILE already exists."
        return 1
    fi

    # Prompt the user for a Unique ID
    while true; do
        read -p "Enter your Unique ID: " UNIQUE_ID

        # Validate Unique ID input
        if [[ "$UNIQUE_ID" =~ ^[0-9]{4,5}$ ]]; then
            break
        else
            echo "Invalid input. Please enter a 4 or 5 digit number."
        fi
    done

    # Ask the user if they want to initialize as a dev or prod scan
    while true; do
        read -p "Do you want to initialize as a dev or prod scan? (dev/prod): " SCAN_TYPE

        # Validate user input
        if [[ "$SCAN_TYPE" == "dev" || "$SCAN_TYPE" == "prod" ]]; then
            break
        else
            echo "Invalid input. Please enter 'dev' or 'prod'."
        fi
    done

    # Create the YAML file with the appropriate content
    {
        echo "tags:"
        if [ "$SCAN_TYPE" == "dev" ]; then
            echo "  - unique-$UNIQUE_ID-dev"
            echo "  # - unique-$UNIQUE_ID-prod"
        else
            echo "  # - unique-$UNIQUE_ID-dev"
            echo "  - unique-$UNIQUE_ID-prod"
        fi
    } > "$YML_FILE"

    echo "The file $YML_FILE has been created."

    # Change to the cloned directory
    cd "$REPO_PATH" || { echo "Error: Failed to change to directory $REPO_PATH"; exit 1; }

    # Check if the directory is a Git repository
    if [ -d ".git" ]; then
        # Add the file to the git repository
        git add "$YML_FILE"
        git commit -m 'Add dynamically created YAML configuration file'
        echo "The file $YML_FILE has been added to the git repository."
    else
        echo "Error: Not a git repository. Initialize the repository first."
    fi
}

# Function: install_semgrep
# Purpose: Install Semgrep using pipx for the target user
install_semgrep() {
    echo "Installing Semgrep..."

    # Determine the target user dynamically
    TARGET_USER="${SUDO_USER:-$(whoami)}"
    TARGET_HOME="/home/$TARGET_USER"

    echo "Target user: $TARGET_USER"
    echo "Target home: $TARGET_HOME"

    # Check if python3-pip and python3-venv are installed
    if ! dpkg -l | grep -q python3-pip; then
        echo "python3-pip not found. Installing python3-pip..."
        sudo apt update
        sudo apt install -y python3-pip
    fi

    if ! dpkg -l | grep -q python3-venv; then
        echo "python3-venv not found. Installing python3-venv..."
        sudo apt update
        sudo apt install -y python3-venv
    fi

    # Install pipx using apt
    if ! command -v pipx &> /dev/null; then
        echo "pipx not found. Installing pipx..."
        sudo apt update
        sudo apt install -y pipx
    fi

    # Ensure pipx is in the PATH for the target user
    echo "Ensuring pipx is in the PATH for $TARGET_USER..."
    sudo -u $TARGET_USER -H bash -c "pipx ensurepath"

    # Source the shell configuration to update the PATH
    echo "Sourcing the shell configuration to update PATH..."
    if [ -f "$TARGET_HOME/.bashrc" ]; then
        sudo -u $TARGET_USER -H bash -c "source $TARGET_HOME/.bashrc"
    fi

    # Check if semgrep is already installed for the target user
    if ! sudo -u $TARGET_USER -H bash -c 'pipx list' | grep -q 'semgrep'; then
        echo "Semgrep is not installed. Proceeding with installation..."
        # Add verbose output and log errors
        sudo -u $TARGET_USER -H bash -c "pipx install semgrep --verbose" 2>&1 | tee semgrep_install.log # Semgrep must be installed with pipx
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "Semgrep installed for $TARGET_USER"
        else
            echo "Failed to install Semgrep for $TARGET_USER. Check semgrep_install.log for details."
            return 1
        fi
    else
        echo "Semgrep is already installed for $TARGET_USER"
    fi

    # Source the shell configuration to update the PATH
    echo "Sourcing the shell configuration to update PATH..."
    if [ -f "$TARGET_HOME/.bashrc" ]; then
        sudo -u $TARGET_USER -H bash -c "source $TARGET_HOME/.bashrc"
    fi

    # Upgrade semgrep using pipx for the target user
    echo "Upgrading Semgrep for $TARGET_USER..."
    sudo -u $TARGET_USER -H bash -c "pipx upgrade semgrep"
    echo "Semgrep upgraded for $TARGET_USER"
}

# Function: create_crontab_entry
# Purpose: Create a crontab entry for running the wrapper script at specified intervals.
create_crontab_entry() {
    # Determine the username of the person who ran the script with sudo
    # This ensures the crontab entry is created for the correct user
    USERNAME="${SUDO_USER:-$(whoami)}"
    SCRIPT_PATH="/home/$USERNAME/run_semgrep.sh"

    echo "Creating crontab entry..."

    # Check if the crontab entry already exists
    # This prevents duplicate entries and ensures the script runs on schedule
    sudo -u $USERNAME crontab -l | grep -F "$CRON_SCHEDULE $SCRIPT_PATH" > /dev/null
    if [ $? -eq 0 ]; then
        echo "Crontab entry already exists with the same schedule and command."
    else
        # Add the crontab entry for the target user
        # This schedules the wrapper script to run at the specified times
        (sudo -u $USERNAME crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $SCRIPT_PATH") | sudo -u $USERNAME crontab -
        if [ $? -eq 0 ]; then
            echo "Crontab entry created: $CRON_SCHEDULE $SCRIPT_PATH"
        else
            echo "Failed to create crontab entry" >&2
            exit 1
        fi
    fi
}

# Function: configure_sudoers
# Purpose: Configure the sudoers file to allow cron service management without a password.
configure_sudoers() {
    echo "Configuring sudoers..."

    # Define the line to be added to the sudoers file
    # This allows the cron service to be started without a password prompt
    SUDOERS_LINE="%sudo ALL=(ALL) NOPASSWD: /usr/sbin/service cron start"
    SUDOERS_FILE="/etc/sudoers.d/cron_nopasswd"

    # Check if the sudoers configuration already exists
    # This prevents duplicate entries and ensures the configuration is applied
    if ! sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
        echo "Configuring sudoers file to allow starting cron without a password..."
        echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to configure sudoers file" >&2
            exit 1
        fi
    else
        echo "Sudoers file already configured."
    fi
}

# Function: check_cron_installed
# Purpose: Check if cron is installed and install it if necessary.
check_cron_installed() {
    if ! [ -x /usr/sbin/cron ]; then
        echo "cron is not installed. Installing cron..."
        sudo apt-get update
        sudo apt-get install -y cron
        if [ $? -ne 0 ]; then
            echo "Failed to install cron" >&2
            exit 1
        fi
    else
        echo "cron is already installed."
    fi
}

# Function: ensure_cron_running
# Purpose: Ensure the cron service is running.
ensure_cron_running() {
    if ! systemctl is-active --quiet cron; then
        echo "Starting cron service..."
        sudo /usr/sbin/service cron start
        if [ $? -ne 0 ]; then
            echo "Failed to start cron service" >&2
            exit 1
        else
            echo "cron service started successfully."
        fi
    else
        echo "cron service is already running."
    fi
}

# Function: create_wrapper_script
# Purpose: Create a wrapper script to run Semgrep with necessary environment setup.
create_wrapper_script() {
    # Determine the username of the person who ran the script with sudo
    # This ensures the script is created in the correct user's home directory
    USERNAME="${SUDO_USER:-$(whoami)}"
    WRAPPER_SCRIPT="/home/$USERNAME/run_semgrep.sh"
    echo "Creating wrapper script at $WRAPPER_SCRIPT"

    # Extract the repository name from the REPO_URL
    # This is used to dynamically set the SEMGREP_REPO_URL for TFVC repositories
    REPO_NAME=$(basename "$REPO_URL" | sed 's/.git$//')

    # Create the wrapper script with the necessary commands and environment setup
    cat <<EOL > $WRAPPER_SCRIPT
#!/bin/bash

# Change to the directory where the repository is located
# This is necessary for running semgrep in the correct context
cd $REPO_PATH

# Check if the repository is a TFVC repository
# If so, set the SEMGREP_REPO_URL to include the repository name
if [[ $REPO_URL == *"tfs"* && $REPO_URL != *"_git"* ]]; then
    export SEMGREP_REPO_URL="local-scan\\$REPO_NAME"
fi

# Execute the semgrep command and redirect output to the log file
# This captures both standard output and errors for troubleshooting
/home/$USERNAME/.local/bin/semgrep ci >> $LOG_FILE 2>&1
EOL

    # Check if the script was created successfully
    if [ $? -eq 0 ]; then
        echo "Wrapper script created successfully at $WRAPPER_SCRIPT"
    else
        echo "Failed to create wrapper script at $WRAPPER_SCRIPT" >&2
        exit 1
    fi

    # Set the wrapper script permissions to executable
    # This is necessary for the script to be run by cron or manually
    chmod +x $WRAPPER_SCRIPT
    if [ $? -eq 0 ]; then
        echo "Wrapper script permissions set to executable"
    else
        echo "Failed to set wrapper script permissions" >&2
        exit 1
    fi
}

# Main Script Execution
# ---------------------
# Execute functions in sequence to set up the environment, install tools, clone repositories, and schedule tasks.

install_git
check_cron_installed
ensure_cron_running
configure_sudoers
clone_repo
create_yml_file
install_semgrep
create_wrapper_script
create_crontab_entry
