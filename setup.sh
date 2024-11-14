#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[+] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_error() { echo -e "${RED}[-] $1${NC}"; }

check_command() {
    if [ $? -ne 0 ]; then
        print_error "Error: $1"
        exit 1
    fi
}

check_command_exists() {
    if ! command -v $1 &> /dev/null; then
        return 1
    fi
    return 0
}

get_permission() {
    local package=$1
    local purpose=$2
    echo -e "${YELLOW}The package '$package' is required $purpose.${NC}"
    read -p "Would you like to install it? (y/n): " choice
    case "$choice" in
        y|Y ) return 0;;
        * ) return 1;;
    esac
}

check_sudo() {
    if ! check_command_exists sudo; then
        print_error "This script requires 'sudo' for some installations. Please install sudo first."
        exit 1
    fi
}

get_shell_config() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        echo "$HOME/.bashrc"
    else
        echo "$HOME/.profile"
    fi
}

setup_node() {
    print_status "Checking Node.js environment..."
    SHELL_CONFIG=$(get_shell_config)
    
    if ! check_command_exists nvm; then
        if get_permission "NVM (Node Version Manager)" "to manage Node.js versions"; then
            print_status "Installing NVM..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            check_command "Failed to install NVM"
            
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
            
            if ! grep -q "NVM_DIR" "$SHELL_CONFIG"; then
                echo 'export NVM_DIR="$HOME/.nvm"' >> "$SHELL_CONFIG"
                echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$SHELL_CONFIG"
                echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> "$SHELL_CONFIG"
            fi
            source "$SHELL_CONFIG"
        else
            print_error "NVM is required to proceed. Exiting."
            exit 1
        fi
    else
        print_status "NVM is already installed"
    fi

    if ! check_command_exists node || [[ $(node -v) != "v18.16.1" ]]; then
        print_status "Installing Node.js 18.16.1..."
        source "$NVM_DIR/nvm.sh"
        nvm install 18.16.1
        check_command "Failed to install Node.js 18.16.1"
    fi

    source "$NVM_DIR/nvm.sh"
    nvm use 18.16.1
    check_command "Failed to set Node.js version"
    print_status "Node.js 18.16.1 is active"
}
setup_pm2() {
    if ! check_command_exists pm2; then
        print_status "Installing PM2..."
        npm install -g pm2
        check_command "Failed to install PM2"
    fi
}

setup_rust() {
    print_status "Checking Rust environment..."
    if ! check_command_exists rustc; then
        if get_permission "Rust" "for building native modules"; then
            print_status "Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            check_command "Failed to install Rust"
            source "$HOME/.cargo/env"
        else
            print_error "Rust is required to proceed. Exiting."
            exit 1
        fi
    else
        print_status "Rust is already installed"
    fi

    current_rust_version=$(rustc --version | cut -d' ' -f2)
    if [[ "$current_rust_version" != "1.74.1" ]]; then
        print_status "Updating Rust to version 1.74.1..."
        rustup install 1.74.1
        check_command "Failed to install Rust 1.74.1"
        rustup default 1.74.1
        check_command "Failed to set Rust version"
    fi
}

setup_build_essentials() {
    print_status "Checking build essentials..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if ! dpkg -l | grep -q build-essential; then
            if get_permission "build-essential" "for compiling packages"; then
                print_status "Installing build essentials..."
                sudo apt-get update
                sudo apt-get install -y build-essential
                check_command "Failed to install build-essential"
            else
                print_error "Build essentials are required to proceed. Exiting."
                exit 1
            fi
        else
            print_status "Build essentials are already installed"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if ! check_command_exists gcc; then
            if get_permission "gcc" "for compiling packages"; then
                print_status "Installing gcc via Homebrew..."
                if ! check_command_exists brew; then
                    print_error "Homebrew is required to install gcc on MacOS."
                    print_error "Please install Homebrew first: https://brew.sh"
                    exit 1
                fi
                brew install gcc
                check_command "Failed to install gcc"
            else
                print_error "GCC is required to proceed. Exiting."
                exit 1
            fi
        else
            print_status "GCC is already installed"
        fi
    else
        print_error "Unsupported operating system"
        exit 1
    fi
}

setup_node_gyp() {
    print_status "Checking node-gyp..."
    if ! check_command_exists python3; then
        print_error "Python 3 is required for node-gyp. Please install Python 3 first."
        exit 1
    fi

    if ! check_command_exists node-gyp; then
        if get_permission "node-gyp" "for building native addons"; then
            print_status "Installing node-gyp..."
            npm i -g node-gyp
            check_command "Failed to install node-gyp"
        else
            print_error "node-gyp is required to proceed. Exiting."
            exit 1
        fi
    else
        print_status "node-gyp is already installed"
    fi

    print_status "Configuring Python for node-gyp..."
    PYTHON_PATH=$(which python3)
    export PYTHON="$PYTHON_PATH"
    check_command "Failed to configure Python for node-gyp"
}

setup_shardeum() {
    cd "$BASE_DIR" || exit 1
    print_status "Setting up Shardeum project..."

    if ! check_command_exists git; then
        if get_permission "git" "to clone the repository"; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                sudo apt-get install -y git
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                brew install git
            fi
            check_command "Failed to install git"
        else
            print_error "Git is required to proceed. Exiting."
            exit 1
        fi
    fi

    if [ -d "shardeum" ]; then
        print_warning "Shardeum directory already exists."
        read -p "Would you like to overwrite it? (y/n): " choice
        if [[ $choice =~ ^[Yy]$ ]]; then
            print_status "Removing existing Shardeum directory..."
            rm -rf shardeum
        else
            print_error "Setup cannot proceed without a fresh installation. Exiting."
            exit 1
        fi
    fi

    git clone https://github.com/shardeum/shardeum.git
    check_command "Failed to clone Shardeum repository"
    cd shardeum || exit 1
    SHARDEUM_DIR="$PWD"
    echo "SHARDEUM_DIR: $SHARDEUM_DIR"

    print_status "Installing npm dependencies..."
    print_warning "This will take a while..."
    npm ci
    check_command "Failed to install npm dependencies"

    print_status "Applying debug patch configuration..."
    if [ -f "src/config/index.ts" ]; then
        cp src/config/index.ts src/config/index.ts.bak
        sed -i.bak -e '
            s/baselineNodes: process.env.baselineNodes ? parseInt(process.env.baselineNodes) : 300/baselineNodes: process.env.baselineNodes ? parseInt(process.env.baselineNodes) : 10/g
            s/minNodes: process.env.minNodes ? parseInt(process.env.minNodes) : 300/minNodes: process.env.minNodes ? parseInt(process.env.minNodes) : 10/g
            s/forceBogonFilteringOn: true/forceBogonFilteringOn: false/g
            s/mode: '\''release'\''/mode: '\''debug'\''/g
            s/startInFatalsLogMode: true/startInFatalsLogMode: false/g
            s/startInErrorLogMode: false/startInErrorLogMode: true/g
        ' src/config/index.ts
        rm -f src/config/index.ts.bak
        print_status "Configuration updated manually"
    else
        print_error "Could not find configuration file to update"
        exit 1
    fi

    print_status "Compiling project..."
    npm run prepare
    check_command "Failed to compile project"

    print_status "Installing Shardus CLI..."
    npm install -g shardus
    check_command "Failed to install Shardus CLI"

    print_status "Updating Shardus archiver..."
    npm update @shardus/archiver
    check_command "Failed to update Shardus archiver"
}

setup_json_rpc() {
    cd .. || exit 1
    print_status "Setting up JSON RPC server..."

    print_status "Cloning JSON RPC server..."
    git clone https://github.com/shardeum/json-rpc-server.git
    check_command "Failed to clone JSON RPC server"

    print_status "Navigating to JSON RPC server directory..."
    cd json-rpc-server || exit 1


    print_status "Installing JSON RPC dependencies..."
    npm install
    check_command "Failed to install JSON RPC dependencies"

    print_status "Compiling JSON RPC server..."
    npm run compile
    check_command "Failed to compile JSON RPC server"
    
    print_status "Starting JSON RPC server..."
    node pm2.js 1
    check_command "Failed to start JSON RPC server"
    print_status "RPC server running at localhost:8080"
}

main() {
    print_status "Starting Shardeum local development environment setup..."
    check_sudo

    DEFAULT_DIR="$(pwd)/shardeum-dev"
    read -p "Enter the base directory path (default: $DEFAULT_DIR): " BASE_DIR
    BASE_DIR=${BASE_DIR:-$DEFAULT_DIR}

    if [ -d "$BASE_DIR" ]; then
        print_warning "Directory $BASE_DIR already exists."
        read -p "Would you like to use this directory anyway? (y/n): " choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            print_error "Please choose a different directory. Exiting."
            exit 1
        fi
    else
        mkdir -p "$BASE_DIR"
    fi

    setup_node
    setup_rust
    setup_build_essentials
    setup_node_gyp
    setup_shardeum

    read -p "Would you like to start a local network with 10 nodes? (y/n): " start_network
    if [[ $start_network =~ ^[Yy]$ ]]; then

        print_status "Starting local network with 10 nodes..."
        shardus start 10
        print_status "Waiting 1m for archiver startup..."
        sleep 60
        setup_json_rpc
    else
        print_status "Setup complete! You can start the network later with:"
        echo "cd $SHARDEUM_DIR && shardus start 10"
        echo "Then wait 1 minute and run:"
        echo "cd $PROJECT_DIR && git clone https://github.com/shardeum/json-rpc-server.git && cd json-rpc-server && npm install && npm start"
    fi

    print_warning "To stop and clean the network run: shardus stop && shardus clean && rm -rf instances in the $SHARDEUM_DIR directory"
}

main