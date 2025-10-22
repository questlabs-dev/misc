#!/bin/bash

# Linkerd Installation/Uninstallation Script
# This script installs or uninstalls Linkerd service mesh with certificates

set -e  # Exit on any error

# Function to install Linkerd
install_linkerd() {
    echo "Starting Linkerd installation..."

    # # Install Linkerd CRDs
    # echo "Installing Linkerd CRDs..."
    # linkerd install --crds | kubectl apply -f -

    # Add the Helm repo for Linkerd edge releases
    echo "Adding Linkerd edge Helm repository..."
    helm repo add linkerd-edge https://helm.linkerd.io/edge
    helm repo update

    # Install Linkerd CRDs via Helm
    echo "Installing Linkerd CRDs via Helm..."
    helm install linkerd-crds linkerd-edge/linkerd-crds \
      -n linkerd --create-namespace --set installGatewayAPI=false

    # Generate certificate key
    echo "Generating certificate key..."
    openssl ecparam -name prime256v1 -genkey -noout -out issuer.key

    # Generate certificate
    echo "Generating certificate..."
    openssl req -x509 -new -nodes -key issuer.key -sha256 -days 3650 -out issuer.crt \
    -subj "/CN=root.linkerd.cluster.local" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" \
    -addext "authorityKeyIdentifier=keyid:always,issuer"

    # Install Linkerd control plane
    echo "Installing Linkerd control plane..."
    helm install linkerd-control-plane \
      -n linkerd \
      --set-file identityTrustAnchorsPEM=issuer.crt \
      --set-file identity.issuer.tls.crtPEM=issuer.crt \
      --set-file identity.issuer.tls.keyPEM=issuer.key \
      linkerd-edge/linkerd-control-plane

    # Install Linkerd CLI (if not already installed)
    echo "Installing Linkerd CLI..."
    if ! command -v linkerd &> /dev/null; then
        curl -sL https://run.linkerd.io/install | sh
        export PATH=$PATH:$HOME/.linkerd2/bin
        echo "Added Linkerd CLI to PATH for current session"
        echo "To permanently add to PATH, add this line to your ~/.bashrc or ~/.profile:"
        echo "export PATH=\$PATH:\$HOME/.linkerd2/bin"
    else
        echo "Linkerd CLI already installed"
    fi

    # Install Linkerd Viz
    echo "Installing Linkerd Viz..."
    linkerd viz install | kubectl apply -f -

    echo "Linkerd installation completed successfully!"
    echo "You can verify the installation with: linkerd check"
}

# Function to uninstall Linkerd
uninstall_linkerd() {
    echo "Starting Linkerd uninstallation..."
    
    # Uninstall Linkerd Viz
    echo "Uninstalling Linkerd Viz..."
    if command -v linkerd &> /dev/null; then
        linkerd viz uninstall | kubectl delete -f - || echo "Linkerd Viz already uninstalled or not found"
    else
        echo "Linkerd CLI not found, skipping Linkerd Viz uninstall"
    fi
    
    # Uninstall Linkerd control plane
    echo "Uninstalling Linkerd control plane..."
    helm uninstall linkerd-control-plane -n linkerd || echo "Linkerd control plane not found"
    
    # Uninstall Linkerd CRDs
    echo "Uninstalling Linkerd CRDs..."
    helm uninstall linkerd-crds -n linkerd || echo "Linkerd CRDs not found"
    
    # Delete Linkerd namespace
    echo "Deleting Linkerd namespace..."
    kubectl delete namespace linkerd || echo "Linkerd namespace not found"
    
    # Delete Linkerd Viz namespace
    echo "Deleting Linkerd Viz namespace..."
    kubectl delete namespace linkerd-viz || echo "Linkerd Viz namespace not found"
    
    # Remove certificate files
    echo "Removing certificate files..."
    rm -f issuer.key issuer.crt
    
    # Remove Helm repo
    echo "Removing Linkerd Helm repository..."
    helm repo remove linkerd-edge || echo "Linkerd edge repo not found"
    
    echo "Linkerd uninstallation completed!"
    echo "Note: Linkerd CLI is still installed. To remove it, delete the ~/.linkerd2 directory manually."
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [install|uninstall|help]"
    echo ""
    echo "Commands:"
    echo "  install     Install Linkerd service mesh (default)"
    echo "  uninstall   Uninstall Linkerd service mesh"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Install Linkerd"
    echo "  $0 install      # Install Linkerd"
    echo "  $0 uninstall    # Uninstall Linkerd"
}

# Main script logic
case "${1:-install}" in
    install)
        install_linkerd
        ;;
    uninstall)
        echo "WARNING: This will completely remove Linkerd from your cluster!"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall_linkerd
        else
            echo "Uninstallation cancelled."
            exit 0
        fi
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac
