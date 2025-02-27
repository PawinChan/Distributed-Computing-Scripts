#!/bin/bash

# Teal Dulcet
# wget -qO - https://raw.github.com/tdulcet/Distributed-Computing-Scripts/master/mlucas.sh | bash -s --
# ./mlucas.sh [PrimeNet User ID] [Computer name] [Type of work] [Idle time to run (mins)]
# ./mlucas.sh "$USER" "$HOSTNAME" 150 10
# ./mlucas.sh ANONYMOUS

DIR="Mlucas"
if [[ $# -gt 4 ]]; then
	echo "Usage: $0 [PrimeNet User ID] [Computer name] [Type of work] [Idle time to run (mins)]" >&2
	exit 1
fi
USERID=${1:-$USER}
COMPUTER=${2:-$HOSTNAME}
TYPE=${3:-150}
TIME=${4:-10}
# COMBO=0
decimal_point=$(locale decimal_point)
date_fmt=$(locale date_fmt)
RE='^(4|1(0[0124]|5[01234]|6[01]))$'
if ! [[ $TYPE =~ $RE ]]; then
	echo "Usage: [Type of work] must be a number" >&2
	exit 1
fi
RE='^([0-9]*\.)?[0-9]+$'
if ! [[ $TIME =~ $RE ]]; then
	echo "Usage: [Idle time to run] must be a number" >&2
	exit 1
fi
echo -e "PrimeNet User ID:\t$USERID"
echo -e "Computer name:\t\t$COMPUTER"
echo -e "Type of work:\t\t$TYPE"
echo -e "Idle time to run:\t$TIME minutes\n"
if [[ -e idletime.sh ]]; then
	bash -- idletime.sh
else
	wget -qO - https://raw.github.com/tdulcet/Distributed-Computing-Scripts/master/idletime.sh | bash -s
fi
if ! command -v make >/dev/null || ! command -v gcc >/dev/null; then
	echo -e "Installing Make and the GNU C compiler"
	echo -e "Please enter your password if prompted.\n"
	apt-get update -y
	apt-get install -y build-essential
fi
if [[ -n $CC ]] && ! command -v "$CC" >/dev/null; then
	echo "Error: $CC is not installed." >&2
	exit 1
fi
if ! command -v python3 >/dev/null; then
	echo "Error: Python 3 is not installed." >&2
	exit 1
fi
files=(/usr/include/gmp*.h)
if ! ldconfig -p | grep -iq 'libgmp\.' || ! [[ -f ${files[0]} ]]; then
	echo -e "Installing the GNU Multiple Precision (GMP) library"
	echo -e "Please enter your password if prompted.\n"
	apt-get update -y
	apt-get install -y libgmp-dev
fi
if ! ldconfig -p | grep -iq 'libhwloc\.' || ! [[ -f /usr/include/hwloc.h ]]; then
	echo -e "Installing the Portable Hardware Locality (hwloc) library"
	echo -e "Please enter your password if prompted.\n"
	apt-get update -y
	apt-get install -y libhwloc-dev
fi
TIME=$(echo "$TIME" | awk '{ printf "%g", $1 * 60 }')

# Adapted from: https://github.com/tdulcet/Linux-System-Information/blob/master/info.sh
echo

if [[ -r /etc/os-release ]]; then
	. /etc/os-release
elif [[ -r /usr/lib/os-release ]]; then
	. /usr/lib/os-release
fi
echo -e "Linux Distribution:\t\t${PRETTY_NAME:-$NAME-$VERSION}"

KERNEL=$(</proc/sys/kernel/osrelease) # uname -r
echo -e "Linux Kernel:\t\t\t$KERNEL"

mapfile -t CPU < <(sed -n 's/^model name[[:blank:]]*: *//p' /proc/cpuinfo | uniq)
if [[ -z $CPU ]]; then
	mapfile -t CPU < <(lscpu | grep -i '^model name' | sed -n 's/^.\+:[[:blank:]]*//p' | uniq)
fi
if [[ -n $CPU ]]; then
	echo -e "Processor (CPU):\t\t${CPU[0]}$([[ ${#CPU[*]} -gt 1 ]] && printf '\n\t\t\t\t%s' "${CPU[@]:1}")"
fi

CPU_THREADS=$(nproc --all) # $(lscpu | grep -i '^cpu(s)' | sed -n 's/^.\+:[[:blank:]]*//p')
if [[ $CPU_THREADS -gt 1 ]]; then
	for ((i = 0; i < CPU_THREADS - 1; ++i)); do
		seq 0 $((1 << 22)) | factor >/dev/null &
	done
fi

sleep 1

CPU_FREQS=($(sed -n 's/^cpu MHz[[:blank:]]*: *//p' /proc/cpuinfo))
if [[ -z $CPU_FREQS ]]; then
	for file in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
		if [[ -r $file ]]; then
			CPU_FREQS=($(awk '{ printf "%g\n", $1 / 1000 }' /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq))
		fi
		break
	done
fi
CPU_FREQ=${CPU_FREQ:+$(printf '%s\n' "${CPU_FREQS[@]}" | sort -nr | head -n 1)}
echo -e "CPU frequency/speed:\t\t$(printf "%'.0f" "${CPU_FREQ/./$decimal_point}") MHz"

wait

HP=$(lscpu | grep -i '^thread(s) per core' | sed -n 's/^.\+:[[:blank:]]*//p' | sort -nr | head -n 1)
CPU_CORES=$(lscpu -ap | grep -v '^#' | cut -d, -f2 | sort -nu | wc -l)
CPU_SOCKETS=$(lscpu -ap | grep -v '^#' | cut -d, -f3 | sort -nu | wc -l)
echo -e "CPU Sockets/Cores/Threads:\t$CPU_SOCKETS/$CPU_CORES/$CPU_THREADS"

CPU_CACHE_SIZES=([1]=$(getconf LEVEL1_DCACHE_SIZE) [2]=$(getconf LEVEL2_CACHE_SIZE) [3]=$(getconf LEVEL3_CACHE_SIZE) [4]=$(getconf LEVEL4_CACHE_SIZE))
if [[ ${CPU_CACHE_SIZES[1]} -eq 0 && ${CPU_CACHE_SIZES[2]} -eq 0 && ${CPU_CACHE_SIZES[3]} -eq 0 && ${CPU_CACHE_SIZES[4]} -eq 0 ]]; then
	for dir in /sys/devices/system/cpu/cpu[0-9]*/cache; do
		if [[ -d $dir ]]; then
			for file in "$dir"/index[0-9]*/size; do
				if [[ -r $file ]]; then
					size=$(numfmt --from=iec <"$file")
					adir=${file%/*}
					level=$(<"$adir/level")
					type=$(<"$adir/type")
					if [[ $type == Instruction ]]; then
						continue
					fi
					CPU_CACHE_SIZES[level]=$size
				fi
			done
		fi
	done
fi
echo -e "CPU Caches:\t\t\tL1: $(printf "%'d" $((CPU_CACHE_SIZES[1] >> 10))) KiB, L2: $(printf "%'d" $((CPU_CACHE_SIZES[2] >> 10))) KiB, L3: $(printf "%'d" $((CPU_CACHE_SIZES[3] >> 10))) KiB, L4: $(printf "%'d" $((CPU_CACHE_SIZES[4] >> 10))) KiB"

ARCHITECTURE=$(getconf LONG_BIT)
echo -e "Architecture:\t\t\t$HOSTTYPE (${ARCHITECTURE}-bit)"

MEMINFO=$(</proc/meminfo)
TOTAL_PHYSICAL_MEM=$(echo "$MEMINFO" | awk '/^MemTotal:/ { print $2 }')
echo -e "Total memory (RAM):\t\t$(printf "%'d" $((TOTAL_PHYSICAL_MEM >> 10))) MiB ($(printf "%'d" $((((TOTAL_PHYSICAL_MEM << 10) / 1000) / 1000))) MB)"

TOTAL_SWAP=$(echo "$MEMINFO" | awk '/^SwapTotal:/ { print $2 }')
echo -e "Total swap space:\t\t$(printf "%'d" $((TOTAL_SWAP >> 10))) MiB ($(printf "%'d" $((((TOTAL_SWAP << 10) / 1000) / 1000))) MB)"

if command -v lspci >/dev/null; then
	mapfile -t GPU < <(lspci 2>/dev/null | grep -i 'vga\|3d\|2d' | sed -n 's/^.*: //p')
fi
if [[ -n $GPU ]]; then
	echo -e "Graphics Processor (GPU):\t${GPU[0]}$([[ ${#GPU[*]} -gt 1 ]] && printf '\n\t\t\t\t%s' "${GPU[@]:1}")"
fi

if [[ -d $DIR ]]; then
	if [[ -d "$DIR/obj" && -x "$DIR/obj/Mlucas" && ! -L "$DIR/obj/mlucas.0.cfg" ]]; then
		echo -e "\nMlucas is already downloaded\n"
		cd "$DIR"
	else
		echo "Error: Mlucas is already downloaded" >&2
		exit 1
	fi
else
	echo -e "\nDownloading Mlucas v21\n"
	if command -v git >/dev/null; then
		git clone https://github.com/primesearch/Mlucas.git
	else
		wget https://github.com/primesearch/Mlucas/archive/main.tar.gz
		echo -e "\nDecompressing the files\n"
		tar -xzvf main.tar.gz
		mv -v Mlucas-main "$DIR"
	fi
	cd "$DIR"
	echo -e "\nBuilding Mlucas\n"
	if ! bash makemake.sh use_hwloc; then
		exit 1
	fi
	cd obj
	make clean
	cd ..
fi
if [[ -f "autoprimenet.py" ]]; then
	echo -e "\nAutoPrimeNet is already downloaded\n"
else
	echo -e "\nDownloading the latest PrimeNet program\n"
	if [[ -e ../autoprimenet.py ]]; then
		cp -v ../autoprimenet.py .
	else
		wget -nv https://raw.github.com/tdulcet/AutoPrimeNet/main/autoprimenet.py
	fi
	chmod +x autoprimenet.py
	python3 -OO -m py_compile autoprimenet.py
fi
echo -e "\nInstalling the Requests library\n"
# python3 -m ensurepip --default-pip || true
python3 -m pip install --upgrade pip || true
if ! python3 -m pip install requests; then
	if command -v pip3 >/dev/null; then
		pip3 install requests
	else
		echo -e "\nWarning: pip3 is not installed and the Requests library may also not be installed\n"
	fi
fi
cd obj
DIR=$PWD
echo -e "\nTesting Mlucas\n"
./Mlucas -fft 192 -iters 100 -radset 0
CORES=()
THREADS=()
ARGS=()
echo -e "\nOptimizing Mlucas for your computer\nThis may take a while…\n"
for ((k = 1; k <= HP; k *= 2)); do
	for ((l = 1; l <= CPU_CORES; l *= 2)); do
		rem=$((CPU_CORES % l))
		if ((rem)); then
			args=()
			for ((i = 0; i < CPU_CORES; i += i == 0 ? rem : l)); do
				arg=$i
				if [[ $l -gt 1 || $k -gt 1 ]]; then
					arg+=":$((i + (i == 0 ? rem : l) - 1))"
					if [[ $k -gt 1 ]]; then
						arg+=":$k"
					fi
				fi
				args+=("$arg")
			done
			if [[ $HP -gt 1 ]]; then
				CORES+=("$k")
			fi
			THREADS+=("$((rem * k)) $((l * k))")
			ARGS+=("${args[*]}")
		fi
		args=()
		for ((i = 0; i < CPU_CORES; i += l)); do
			arg=$i
			if [[ $l -gt 1 || $k -gt 1 ]]; then
				temp=$((i + l - 1))
				arg+=":$((temp < CPU_CORES ? temp : CPU_CORES - 1))"
				if [[ $k -gt 1 ]]; then
					arg+=":$k"
				fi
			fi
			args+=("$arg")
		done
		if [[ $HP -gt 1 ]]; then
			CORES+=("$k")
		fi
		if ((rem)); then
			THREADS+=("$((l * k)) $((rem * k))")
		else
			THREADS+=("$((l * k))")
		fi
		ARGS+=("${args[*]}")
	done
done
echo "Combinations of CPU cores/threads to benchmark"
{
	echo -e "#\tWorkers/Runs\tThreads\t-core arguments"
	for i in "${!ARGS[@]}"; do
		args=(${ARGS[i]})
		printf "%'d\t%'d\t%s\t%s\n" $((i + 1)) ${#args[*]} "${THREADS[i]// /, }" "${args[*]}"
	done
} | column -t -s $'\t' | tee -a bench.txt
echo
# https://www.mersenneforum.org/showpost.php?p=569485&postcount=71
TIMES=()
FFTS=()
RADICES=()
if [[ -e mlucas.cfg ]]; then
	rm -v mlucas.cfg
fi
for i in "${!ARGS[@]}"; do
	args=(${ARGS[i]})
	threads=(${THREADS[i]})
	times=()
	ffts=()
	radices=()
	for j in "${!threads[@]}"; do
		index=$((j == 0 ? 0 : -1))
		printf "\n#%'d\tThreads: %s\t(-core argument: %s)\n\n" $((i + 1)) "${threads[j]}" "${args[index]}"
		file="mlucas.${CORES:+${CORES[i]}c.}${threads[j]}t.$j.cfg"
		if [[ ! -e $file ]]; then
			# for ((k = 7; k < 12; ++k)); do
				# m=$((1 << k))
				# for l in {8..15}; do
					# fft=$((l * m))
					# printf '\n\tFFT length: %sK (%s)\n\n' $fft "$(numfmt --from=iec --to=iec ${fft}K)"
					# time ./Mlucas -fft $fft -core "${args[index]}"
				# done
			# done
			for s in m; do # tt t s m l h
				time stdbuf -oL ./Mlucas -s $s -core "${args[index]}" |& tee -a "test.${CORES:+${CORES[i]}c.}${threads[j]}t.$j.log" | grep -i 'error\|warn\|assert\|info\|fft length\|fft radices'
			done
			if [[ ! -e mlucas.cfg ]]; then
				>mlucas.cfg
			fi
			mv mlucas.cfg "$file"
		fi
		times+=("$(awk 'BEGIN { fact='$(((${#CORES[*]} == 0 ? threads[j] : threads[j] / CORES[i]) * (${#threads[*]} == 1 ? ${#args[*]} : ((threads[0] < threads[1] && j == 0) || (threads[0] > threads[1] && j == 1) ? 1 : ${#args[*]} - 1))))'/'${#args[*]}' } /^[[:space:]]*#/ || NF<4 { next } { printf "%.15g\n", $4*fact }' "$file")")
		ffts+=("$(awk '/^[[:space:]]*#/ || NF<4 { next } { print $1 }' "$file")")
		radices+=("$(awk '/^[[:space:]]*#/ || NF<4 { next } { for(i=11;i<=NF && $i!=0;++i) printf "%s%s", $i, i==NF || $(i+1)==0 ? RS : OFS }' "$file")")
	done
	if [[ ${#threads[*]} -eq 1 ]]; then
		TIMES+=("${times[0]}")
		FFTS+=("${ffts[0]}")
		RADICES+=("${radices[0]// /,}")
	else
		mapfile -t atimes <<<"${times[0]}"
		mapfile -t times <<<"${times[1]}"
		mapfile -t affts <<<"${ffts[0]}"
		mapfile -t ffts <<<"${ffts[1]}"
		mapfile -t aradices <<<"${radices[0]}"
		mapfile -t radices <<<"${radices[1]}"
		TIMES+=("$(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
			echo "${atimes[k]} ${times[j]}"
			break
		fi; done; done | awk '{ printf "%.15g\n", $1 + $2 }')")
		FFTS+=("$(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
			echo "${affts[k]}"
			break
		fi; done; done)")
		RADICES+=("$(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
			printf '%s\t%s\n' "${aradices[k]// /,}" "${radices[j]// /,}"
			break
		fi; done; done)")
	fi
done
# MIN=0
# mapfile -t affts <<<"${FFTS[MIN]}"
# atimes=(${TIMES[MIN]})
# for i in "${!TIMES[@]}"; do
	# if ((i)); then
		# mapfile -t ffts <<<"${FFTS[i]}"
		# times=(${TIMES[i]})
		# mean=$(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
			# printf '%s\t%s\n' "${atimes[k]}" "${times[j]}"
			# break
		# fi; done; done | awk '{ sum+=$1/$2 } END { printf "%.15g\n", sum / NR }')
		# if (($(echo "$mean" | awk '{ print ($1>1) }'))); then
			# MIN=$i
			# affts=("${ffts[@]}")
			# atimes=("${times[@]}")
		# fi
	# fi
# done
files=()
trap 'rm "${files[@]}"' EXIT
for ((i = 0; i < CPU_CORES; ++i)); do
	if [[ -d /dev/shm ]]; then
		file=$(mktemp -p /dev/shm)
	else
		file=$(mktemp)
	fi
	files+=("$file")
done
ITERS=()
for i in "${!ARGS[@]}"; do
	args=(${ARGS[i]})
	threads=(${THREADS[i]})
	mapfile -t ffts <<<"${FFTS[i]}"
	mapfile -t aradices <<<"${RADICES[i]}"
	iters=()
	printf "\n#%'d\tWorkers/Runs: %'d\tThreads: %s\n" $((i + 1)) ${#args[*]} "${THREADS[i]// /, }"
	printf "[%($date_fmt)T]\n" -1 >>bench.txt
	if [[ -n $ffts ]]; then
		for j in "${!ffts[@]}"; do
			printf '\n\tTiming FFT length: %sK (%s)\n\n' "${ffts[j]}" "$(numfmt --from=iec --to=iec "${ffts[j]}K")"
			radices=(${aradices[j]})
			for k in "${!args[@]}"; do
				stdbuf -oL ./Mlucas -fft "${ffts[j]}" -iters 1000 -radset "${radices[${#threads[*]} == 1 || (threads[0] < threads[1] && k == 0) || (threads[0] > threads[1] && k < ${#args[*]} - 1) ? 0 : 1]}" -core "${args[k]}" >&"${files[k]}" &
			done
			wait
			grep -ih 'error\|warn\|assert\|clocks' "${files[@]::${#args[*]}}"
			if grep -iq 'fatal\|halt' "${files[@]::${#args[*]}}"; then
				echo
				for k in "${!args[@]}"; do
					stdbuf -oL ./Mlucas -fft "${ffts[j]}" -iters 1000 -radset "${radices[${#threads[*]} == 1 || (threads[0] < threads[1] && k == 0) || (threads[0] > threads[1] && k < ${#args[*]} - 1) ? 0 : 1]}" -core "${args[k]}" -shift $RANDOM >&"${files[k]}" &
				done
				wait
				grep -ih 'error\|warn\|assert\|clocks' "${files[@]::${#args[*]}}"
			fi
			times=($(sed -n 's/^Clocks = //p' "${files[@]::${#args[*]}}" | awk -F'[:.]' '{ printf "%.15g\n", (($1*60*60*1000)+($2*60*1000)+($3*1000)+$4)/1000 }'))
			throughput=$(printf '%s\n' "${times[@]}" | awk '{ sum+=1/$1 } END { printf "%.15g\n", 1000 * sum }')
			echo
			{
				printf "Timings for %sK FFT length (%'d cores, %s threads, %'d workers): " "${ffts[j]}" "$CPU_CORES" "${THREADS[i]// /, }" ${#args[*]}
				for k in "${!times[@]}"; do
					if ((k)); then
						printf ', '
					fi
					printf "%'5.2f" "${times[k]/./$decimal_point}"
				done
				printf " ms.  Throughput: %'5.3f iter/sec.\n" "${throughput/./$decimal_point}"
			} | tee -a bench.txt
			iters+=("$throughput")
		done
	fi
	ITERS+=("$(printf '%s\n' "${iters[@]}")")
done
MAX=0
mapfile -t affts <<<"${FFTS[MAX]}"
aiters=(${ITERS[MAX]})
for i in "${!ITERS[@]}"; do
	if ((i)); then
		mapfile -t ffts <<<"${FFTS[i]}"
		iters=(${ITERS[i]})
		if [[ -n $ffts ]]; then
			mean=$(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
				printf '%s\t%s\n' "${aiters[k]}" "${iters[j]}"
				break
			fi; done; done | awk '{ sum+=$1/$2 } END { printf "%.15g\n", sum / NR }')
			if (($(echo "$mean" | awk '{ print $1<1 }'))); then
				MAX=$i
				affts=("${ffts[@]}")
				aiters=("${iters[@]}")
			fi
		fi
	fi
done
RUNS=(${ARGS[MAX]})
threads=(${THREADS[MAX]})
{
	echo -e "\nBenchmark Summary\n"
	echo -e "\tAdjusted msec/iter times (ms/iter) vs Actual iters/sec total throughput (iter/s) for each combination\n"
	{
		printf 'FFT\t'
		for i in "${!ARGS[@]}"; do
			if ((i)); then
				printf '\t \t'
			fi
			printf "#%'d" $((i + 1))
		done
		echo
		printf 'length\t'
		for i in "${!ARGS[@]}"; do
			printf 'ms/iter\titer/s\t'
		done
		echo
		mapfile -t affts < <(printf '%s\n' "${FFTS[@]}" | sed '/^$/d' | sort -nu)
		for k in "${!affts[@]}"; do
			printf '%sK\t' "${affts[k]}"
			for i in "${!ITERS[@]}"; do
				mapfile -t ffts <<<"${FFTS[i]}"
				iters=(${ITERS[i]})
				times=(${TIMES[i]})
				for ((j = k >= ${#ffts[*]} ? ${#ffts[*]} - 1 : k; j >= 0; --j)); do
					if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
						break
					fi
				done
				if [[ $j -ge 0 ]]; then
					printf "%'g\t%'.3f\t" "${times[j]/./$decimal_point}" "${iters[j]/./$decimal_point}"
				else
					printf -- '-\t-\t'
				fi
			done
			echo
		done
	} | column -t -s $'\t'
	echo
	echo "Fastest combination"
	{
		echo -e "#\tWorkers/Runs\tThreads\tFirst -core argument"
		printf "%'d\t%'d\t%s\t%s\n" $((MAX + 1)) ${#RUNS[*]} "${THREADS[MAX]// /, }" "${RUNS[0]}$(if [[ ${#threads[*]} -gt 1 ]]; then echo "  ${RUNS[-1]}"; fi)"
	} | column -t -s $'\t'
	echo
	if [[ ${#ARGS[*]} -gt 1 ]]; then
		{
			echo -e "Mean ± σ std dev faster\t#\tWorkers/Runs\tThreads\tFirst -core argument"
			for i in "${!ARGS[@]}"; do
				if [[ $i -ne $MAX ]]; then
					args=(${ARGS[i]})
					threads=(${THREADS[i]})
					mapfile -t ffts <<<"${FFTS[i]}"
					iters=(${ITERS[i]})
					if [[ -n $ffts ]]; then
						# join -o 1.2,2.2 <(paste <(echo "${FFTS[MAX]}") <(echo "${ITERS[MAX]}")) <(paste <(echo "${FFTS[i]}") <(echo "${ITERS[i]}"))
						array=($(for k in "${!affts[@]}"; do for j in "${!ffts[@]}"; do if [[ ${affts[k]} -eq ${ffts[j]} ]]; then
							printf '%s\t%s\n' "${aiters[k]}" "${iters[j]}"
							break
						fi; done; done | awk '{ sum+=$1/$2; sumsq+=($1/$2)^2 } END { mean=sum/NR; variance=sumsq/NR-mean^2; printf "%.15g\t%.15g\t%.15g\n", mean, sqrt(variance<0 ? 0 : variance), (mean * 100) - 100 }'))
						printf "%'.3f ± %'.3f (%'.1f%%)\t%'d\t%'d\t%s\t%s\n" "${array[0]/./$decimal_point}" "${array[1]/./$decimal_point}" "${array[2]/./$decimal_point}" $((i + 1)) ${#args[*]} "${THREADS[i]// /, }" "${args[0]}$(if [[ ${#threads[*]} -gt 1 ]]; then echo "  ${args[-1]}"; fi)"
					else
						printf -- "-\t%'d\t%'d\t%s\t%s\n" $((i + 1)) ${#args[*]} "${THREADS[i]// /, }" "${args[0]}$(if [[ ${#threads[*]} -gt 1 ]]; then echo "  ${args[-1]}"; fi)"
					fi
				fi
			done
		} | column -t -s $'\t'
	fi
	echo
} | tee -a bench.txt
echo "The benchmark data was written to the 'bench.txt' file"
if [[ -n $COMBO ]]; then
	printf "\nUsing combination: %'d\n" $((COMBO + 1))
	RUNS=(${ARGS[COMBO]})
	threads=(${THREADS[COMBO]})
	MAX=$COMBO
fi
for j in "${!threads[@]}"; do
	ln -s "mlucas.${CORES:+${CORES[MAX]}c.}${threads[j]}t.$j.cfg" "mlucas.$j.cfg"
done
echo -e "\nRegistering computer with PrimeNet\n"
total=$((TOTAL_PHYSICAL_MEM >> 10))
python3 -OO ../autoprimenet.py -t 0 -T "$TYPE" -u "$USERID" --num-workers ${#RUNS[*]} -m -H "$COMPUTER" --cpu-model="${CPU[0]}" --frequency="$(if [[ -n $CPU_FREQ ]]; then printf "%.0f" "${CPU_FREQ/./$decimal_point}"; else echo "1000"; fi)" --memory=$total --max-memory="$(echo $total | awk '{ printf "%d", $1 * 0.9 }')" --cores="$CPU_CORES" --hyperthreads="$HP" --l1=$((CPU_CACHE_SIZES[1] ? CPU_CACHE_SIZES[1] >> 10 : 8)) --l2=$((CPU_CACHE_SIZES[2] ? CPU_CACHE_SIZES[2] >> 10 : 512)) --l3=$((CPU_CACHE_SIZES[3] >> 10))
maxalloc=$(echo ${#RUNS[*]} | awk '{ printf "%g", 90 / $1 }')
args=()
for i in "${!RUNS[@]}"; do
	dir="run$i"
	mkdir "$dir"
	pushd "$dir" >/dev/null
	ln -s ../mlucas.$((${#threads[*]} == 1 || (threads[0] < threads[1] && i == 0) || (threads[0] > threads[1] && i < ${#RUNS[*]} - 1) ? 0 : 1)).cfg mlucas.cfg
	# ln -s ../prime.ini .
	args+=(-D "$dir")
	popd >/dev/null
done
echo -e "\nStarting AutoPrimeNet\n"
nohup python3 -OO ../autoprimenet.py "${args[@]}" >>'autoprimenet.out' &
sleep $((${#RUNS[*]} * 2))
for i in "${!RUNS[@]}"; do
	printf "\nWorker/CPU Core %'d: (-core argument: %s)\n" $((i + 1)) "${RUNS[i]}"
	pushd "run$i" >/dev/null
	echo -e "\n\tStarting Mlucas\n"
	nohup nice ../Mlucas -core "${RUNS[i]}" -maxalloc "$maxalloc" >>'Mlucas.out' &
	sleep 1
	popd >/dev/null
done
# maxalloc=$(echo ${#RUNS[*]} | awk '{ printf "%g", 90 / sqrt($1) }')
cat <<EOF >jobs.sh
#!/bin/bash

# Copyright © 2020 Teal Dulcet
# Start Mlucas and AutoPrimeNet
# Run: ./jobs.sh

set -e

# Mlucas maximum memory usage precentage per worker
maxalloc=$maxalloc

pgrep -x Mlucas >/dev/null || {
	echo -e "\nStarting Mlucas\n"
	set -x
	$(for i in "${!RUNS[@]}"; do
		((i)) && printf '\t'
		echo "(cd 'run$i' && exec nohup nice ../Mlucas -core ${RUNS[i]} -maxalloc \$maxalloc >>'Mlucas.out' &) "
	done)
}

pgrep -f '^python3 -OO \.\./autoprimenet\.py' >/dev/null || {
	echo -e "\nStarting AutoPrimeNet\n"
	set -x
	exec nohup python3 -OO ../autoprimenet.py ${args[@]} >>'autoprimenet.out' &
}
EOF
chmod +x jobs.sh
#crontab -l | { cat; echo "@reboot cd ${DIR@Q} && ./jobs.sh"; } | crontab -
cat <<EOF >Mlucas.sh
#!/bin/bash

# Copyright © 2020 Teal Dulcet
# Start Mlucas and AutoPrimeNet if the computer has not been used in the specified idle time and stop it when someone uses the computer
# ${DIR@Q}/Mlucas.sh

NOW=\${EPOCHSECONDS:-\$(date +%s)}

if who -s | awk '{ print \$2 }' | (cd /dev && xargs -r stat -c '%U %X') | awk '{if ('"\$NOW"'-\$2<$TIME) { print \$1"\t"'"\$NOW"'-\$2; ++count }} END{if (count>0) { exit 1 }}' >/dev/null; then
	cd ${DIR@Q} && ./jobs.sh
else
	pgrep -x Mlucas >/dev/null && killall -9 Mlucas
fi
EOF
chmod +x Mlucas.sh
echo -e "\nRun this command for it to start if the computer has not been used in the specified idle time and stop it when someone uses the computer:\n"
echo "crontab -l | { cat; echo \"* * * * * ${DIR@Q}/Mlucas.sh\"; } | crontab -"
echo -e "\nTo edit the crontab, run \"crontab -e\""
