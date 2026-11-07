#!/usr/bin/env bash
# Qubit-cap sweep (Grok plan v2, madde 1).
# Env var vermek ise yaramaz: mod.rs bu degerleri derlenmis bind81_recipe.txt'den
# set_var ile ezer. Bu yuzden recipe dosyasini degistirip her deger icin yeniden
# benchmark aliyoruz; cikista recipe orijinaline doner.
# Kullanim: ./sweep_cap.sh            (varsayilan degerler)
#           ./sweep_cap.sh 1224 1216  (kendi degerlerin)
set -u
cd "$(dirname "$0")"
R=src/point_add/bind81_recipe.txt
cp "$R" /tmp/bind81_recipe.orig
trap 'cp /tmp/bind81_recipe.orig "$R"; echo "recipe geri yuklendi"' EXIT

BASE=890237600   # 724359.316 * 1229
CAPS=("$@"); [ ${#CAPS[@]} -eq 0 ] && CAPS=(1224 1216 1208 1200 1184)
SUMMARY=sweep_summary.txt
echo "cap  toffoli  qubits  score  vs_base" > "$SUMMARY"

for q in "${CAPS[@]}"; do
  cp /tmp/bind81_recipe.orig "$R"
  sed -i.bak -e "s/^HEO_PIN_PP_WALK_MAX_QUBITS=.*/HEO_PIN_PP_WALK_MAX_QUBITS=$q/" \
             -e "s/^LFA2_SET_HEO_PIN_PP_WALK_MAX_QUBITS=.*/LFA2_SET_HEO_PIN_PP_WALK_MAX_QUBITS=$q/" \
             -e "s/^LF_SQUARE_CAP=.*/LF_SQUARE_CAP=$q/" "$R" && rm -f "$R.bak"
  echo "===== cap=$q ====="
  log="sweep_$q.log"
  ./benchmark.sh --note "cap sweep q=$q" > "$log" 2>&1
  t=$(grep -m1 "avg executed Toffoli" "$log" | awk -F: '{gsub(/ /,"",$2);print $2}')
  n=$(grep -m1 -E "^ *qubits *:" "$log" | awk -F: '{gsub(/ /,"",$2);print $2}')
  if grep -q "experiment OK" "$log" && [ -n "$t" ] && [ -n "$n" ]; then
    s=$(awk -v t="$t" -v n="$n" 'BEGIN{printf "%.0f", t*n}')
    p=$(awk -v s="$s" -v b="$BASE" 'BEGIN{printf "%+.2f%%", (s/b-1)*100}')
    echo "$q  $t  $n  $s  $p" | tee -a "$SUMMARY"
  else
    echo "$q  FAIL (bkz. $log)" | tee -a "$SUMMARY"
  fi
done
echo; cat "$SUMMARY"
