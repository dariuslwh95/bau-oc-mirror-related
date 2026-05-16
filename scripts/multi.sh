# Define your files in the exact order you want them to process
ISCS=(
  "../inbox/imageset-4.16.61-platform.yaml"
  "../inbox/imageset-4.19-operators.yaml"
  "../inbox/imageset-4.20-operators.yaml"
)

for isc in "${ISCS[@]}"; do
    if [ -f "$isc" ]; then
        echo -e "\n========================================================"
        echo "🚀 STARTING MIRROR PROCESS FOR: $isc"
        echo -e "========================================================\n"
        
        python3 main.py "$isc"
    else
        echo "⚠️ Skipping: $isc (File not found)"
    fi

    echo -e "\n========================================================"
    echo "🚩 DONE"
    echo -e "========================================================\n" 
done