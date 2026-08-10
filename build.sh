./cleanup.sh &&

folder="src"
args=()

while IFS= read -r -d '' file; do
    base="${file%.*}"
    out="${base}.luau"
    args+=("$file" "$out")
done < <(find "$folder" -type f -name "*.z" -print0)

z --lang lua --verbose --pretty "${args[@]}"