cat > ~/sdr2hdr.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

OUTPUT_DIR="/sdcard/DCIM/HDR10_Converted"
TMP_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

mkdir -p "$OUTPUT_DIR" "$TMP_DIR"
rm -f "$OUTPUT_DIR/.nomedia"

# 24-bit TrueColor Palette
C_RESET=$'\e[0m'
C_BOLD=$'\e[1m'
C_CYAN=$'\e[38;2;56;189;248m'     # #38bdf8 Electric Sky Blue (Borders & Keywords)
C_YELLOW=$'\e[38;2;250;204;21m'   # #facc15 Vibrant Yellow (Category Headers & Highlights)
C_GREEN=$'\e[38;2;74;222;128m'    # #4ade80 Mint / Lime (Values & Success)
C_WHITE=$'\e[38;2;248;250;252m'   # #f8fafc Crisp Off-White (Text & [Numbers])
C_GRAY=$'\e[38;2;148;163;184m'    # #94a3b8 Slate Gray (Hints & Inactive Bar)
C_ALERT=$'\e[38;2;244;63;94m'     # #f43f5e Coral Pink (Alerts & Cancellations)
C_VRED=$'\e[38;2;255;49;49m'      # #ff3131 Vibrant Neon Red (Back Prompt)

cleanup_exit() {
    [ -n "$LISTENER_PID" ] && kill "$LISTENER_PID" 2>/dev/null
    [ -n "$FIFO" ] && rm -f "$FIFO"
    [ -n "$STOP_FLAG" ] && rm -f "$STOP_FLAG"
    termux-wake-unlock 2>/dev/null
    stty sane 2>/dev/null
}
trap cleanup_exit EXIT INT TERM

get_term_width() {
    local w
    w=$(tput cols 2>/dev/null)
    if [[ -z "$w" || "$w" -le 0 ]]; then
        w="${COLUMNS:-42}"
    fi
    echo "$w"
}

print_center() {
    local text="$1"
    local term_w
    term_w=$(get_term_width)

    local clean
    clean=$(printf '%s' "$text" | sed -E $'s/\e\\[[0-9;]*[a-zA-Z]//g')
    local len=${#clean}

    local pad=$(( (term_w - len) / 2 ))
    [ "$pad" -lt 0 ] && pad=0

    printf "%*s%s\n" "$pad" "" "$text"
}

print_divider() {
    local char="${1:-=}"
    local color="${2:-$C_CYAN}"
    local term_w
    term_w=$(get_term_width)

    local line_len=42
    [ "$term_w" -lt 42 ] && line_len="$term_w"

    local pad=$(( (term_w - line_len) / 2 ))
    [ "$pad" -lt 0 ] && pad=0

    local line
    line=$(printf "%*s" "$line_len" "" | tr ' ' "$char")
    printf "%*s%s%s%s\n" "$pad" "" "$color" "$line" "$C_RESET"
}

get_video_meta() {
    local file="$1"
    local bytes
    bytes=$(stat -c%s "$file" 2>/dev/null || ls -nl "$file" | awk '{print $5}')
    local size_mb
    size_mb=$(awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b / 1048576}')

    local info
    info=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,nb_frames,r_frame_rate,duration \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=0 "$file" 2>/dev/null)

    local w h frames r_fps dur
    w=$(echo "$info" | grep '^width=' | cut -d= -f2)
    h=$(echo "$info" | grep '^height=' | cut -d= -f2)
    frames=$(echo "$info" | grep '^nb_frames=' | cut -d= -f2)
    r_fps=$(echo "$info" | grep '^r_frame_rate=' | cut -d= -f2)
    dur=$(echo "$info" | grep '^duration=' | head -n1 | cut -d= -f2)

    local quality="SD"
    local max_dim=$(( w > h ? w : h ))
    local min_dim=$(( w < h ? w : h ))

    if [ "$max_dim" -ge 3840 ] || [ "$min_dim" -ge 2160 ]; then
        quality="UHD"
    elif [ "$max_dim" -ge 1920 ] || [ "$min_dim" -ge 1080 ]; then
        quality="FHD"
    elif [ "$max_dim" -ge 1280 ] || [ "$min_dim" -ge 720 ]; then
        quality="HD"
    fi

    if [ -z "$frames" ] || [ "$frames" = "N/A" ]; then
        if [ -n "$dur" ] && [ "$dur" != "N/A" ] && [ -n "$r_fps" ]; then
            frames=$(awk -v d="$dur" -v fps="$r_fps" 'BEGIN {
                split(fps, a, "/");
                val = (length(a) > 1 && a[2] > 0) ? a[1]/a[2] : a[1];
                printf "%.0f", d * val;
            }')
        else
            frames="N/A"
        fi
    fi

    local dur_str="N/A"
    if [ -n "$dur" ] && [ "$dur" != "N/A" ]; then
        dur_str=$(awk -v d="$dur" 'BEGIN {
            sec = int(d);
            m = int(sec / 60);
            s = sec % 60;
            printf "%02d:%02d", m, s;
        }')
    fi

    echo "${C_GREEN}$size_mb${C_RESET} ${C_CYAN}|${C_RESET} ${C_YELLOW}$quality${C_RESET} ${C_CYAN}|${C_RESET} ${C_WHITE}$frames frames${C_RESET} ${C_CYAN}|${C_RESET} ${C_GRAY}d: $dur_str${C_RESET}"
}

STEP=0

if [ -n "$1" ]; then
    if [ -f "$1" ]; then
        INPUT_FILE="$1"
        STEP=2
    elif [ -d "$1" ]; then
        SELECTED_DIR="$1"
        STEP=1
    else
        echo "${C_ALERT}[✗] Error: Path '$1' not found.${C_RESET}"
        STEP=0
    fi
fi

while true; do
    case "$STEP" in
        0)
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Select a Folder${C_RESET}"
            print_divider "=" "$C_CYAN"

            folder_list=()
            raw_dirs=()
            while IFS= read -r dir; do
                [ -n "$dir" ] && raw_dirs+=("$dir")
            done < <(find /sdcard/DCIM /sdcard/Download /sdcard/Movies /sdcard/Pictures -maxdepth 2 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -exec dirname {} + 2>/dev/null | sort -u)

            if [ ${#raw_dirs[@]} -eq 0 ]; then
                echo "${C_ALERT}[!] No standard video folders detected.${C_RESET}"
                echo "  ${C_WHITE}[m]${C_RESET} ${C_YELLOW}Enter custom folder path${C_RESET}"
            else
                current_grp=""
                idx=1

                for d in "${raw_dirs[@]}"; do
                    folder_list+=("$d")
                    rel="${d#/sdcard/}"
                    grp="${rel%%/*}"
                    sub="${rel#*/}"

                    if [ "$grp" = "$sub" ]; then
                        sub="(Root Folder)"
                    fi

                    if [ "$grp" != "$current_grp" ]; then
                        echo ""
                        echo "  ${C_YELLOW}── $grp ──${C_RESET}"
                        current_grp="$grp"
                    fi

                    printf "    ${C_WHITE}[%d]${C_RESET} ${C_BOLD}${C_WHITE}%s${C_RESET}\n" "$idx" "$sub"
                    ((idx++))
                done

                echo ""
                print_divider "-" "$C_CYAN"
                echo "  ${C_WHITE}[m]${C_RESET} ${C_GRAY}Enter custom path manually${C_RESET}"
            fi

            echo ""
            printf "${C_CYAN}Enter number or ${C_ALERT}[q]${C_CYAN}uit:${C_RESET} "
            read -r fchoice

            if [[ "$fchoice" =~ ^[qQ]$ ]]; then
                echo "${C_ALERT}Exiting.${C_RESET}"
                exit 0
            fi

            if [[ "$fchoice" =~ ^[mM]$ ]]; then
                printf "${C_CYAN}Enter full directory path: ${C_RESET}"
                read -r custom_dir
                if [ -d "$custom_dir" ]; then
                    SELECTED_DIR="$custom_dir"
                    STEP=1
                else
                    echo "${C_ALERT}[!] Directory does not exist.${C_RESET}"
                fi
                continue
            fi

            if ! [[ "$fchoice" =~ ^[0-9]+$ ]] || [ "$fchoice" -lt 1 ] || [ "$fchoice" -gt "${#folder_list[@]}" ]; then
                echo "${C_ALERT}[!] Invalid choice. Please try again.${C_RESET}"
                continue
            fi

            SELECTED_DIR="${folder_list[$((fchoice - 1))]}"
            STEP=1
            ;;

        1)
            shopt -s nullglob nocaseglob
            raw_files=("$SELECTED_DIR"/*.mp4 "$SELECTED_DIR"/*.mkv "$SELECTED_DIR"/*.mov "$SELECTED_DIR"/*.webm)

            video_list=()
            for f in "${raw_files[@]}"; do
                base="$(basename "$f")"
                if [[ "$base" != trashed-* && "$base" != output_HDR10* ]]; then
                    video_list+=("$f")
                fi
            done

            if [ ${#video_list[@]} -eq 0 ]; then
                echo ""
                echo "${C_ALERT}[✗] No valid videos found in: $SELECTED_DIR${C_RESET}"
                STEP=0
                continue
            fi

            disp_folder="${SELECTED_DIR#/sdcard/}"
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Select a Video to Convert${C_RESET}"
            print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
            print_center "${C_CYAN}Folder: ${C_YELLOW}$disp_folder${C_RESET}"
            print_divider "=" "$C_CYAN"
            for i in "${!video_list[@]}"; do
                f="${video_list[$i]}"
                meta=$(get_video_meta "$f")
                printf "  ${C_WHITE}[%d]${C_RESET} ${C_BOLD}${C_WHITE}%s${C_RESET}\n      ${C_CYAN}└─${C_RESET} %b\n" "$((i + 1))" "$(basename "$f")" "$meta"
            done
            echo ""
            printf "${C_CYAN}Enter number ${C_WHITE}(1-%d)${C_CYAN} or ${C_ALERT}[q]${C_CYAN}uit:${C_RESET} " "${#video_list[@]}"
            read -r choice

            if [[ "$choice" =~ ^[qQ]$ ]]; then
                echo "${C_ALERT}Exiting.${C_RESET}"
                exit 0
            fi

            if [[ "$choice" =~ ^[bB]$ ]]; then
                STEP=0
                continue
            fi

            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#video_list[@]}" ]; then
                echo "${C_ALERT}[!] Invalid choice. Please choose a valid number.${C_RESET}"
                continue
            fi

            INPUT_FILE="${video_list[$((choice - 1))]}"
            STEP=2
            ;;

        2)
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Adjust Grading Settings${C_RESET}"
            print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
            print_divider "=" "$C_CYAN"
            printf "${C_WHITE}Exposure${C_RESET} ${C_GRAY}[-3.0 to 3.0]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}0.25${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_exp
            if [[ "$input_exp" =~ ^[bB]$ ]]; then STEP=1; continue; fi
            EXPOSURE="${input_exp:-0.25}"

            printf "${C_WHITE}Highlight / MaxCLL${C_RESET} ${C_GRAY}[nits]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}240${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_hl
            if [[ "$input_hl" =~ ^[bB]$ ]]; then STEP=1; continue; fi
            HIGHLIGHT="${input_hl:-240}"

            printf "${C_WHITE}Saturation${C_RESET} ${C_GRAY}[0.0 to 3.0]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}1.25${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_sat
            if [[ "$input_sat" =~ ^[bB]$ ]]; then STEP=1; continue; fi
            SATURATION="${input_sat:-1.25}"

            STEP=3
            ;;

        3)
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Select Encoder Preset${C_RESET}"
            print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
            print_divider "=" "$C_CYAN"
            echo "  ${C_WHITE}[1]${C_RESET} ${C_CYAN}ultrafast${C_RESET} ${C_GRAY}(Fastest render)${C_RESET}"
            echo "  ${C_WHITE}[2]${C_RESET} ${C_CYAN}fast${C_RESET}      ${C_GRAY}(Default balanced)${C_RESET}"
            echo "  ${C_WHITE}[3]${C_RESET} ${C_CYAN}medium${C_RESET}    ${C_GRAY}(Better compression)${C_RESET}"
            echo "  ${C_WHITE}[4]${C_RESET} ${C_CYAN}slow${C_RESET}      ${C_GRAY}(Highest quality)${C_RESET}"
            printf "${C_CYAN}Enter preset ${C_WHITE}[1-4]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}2${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_preset

            if [[ "$input_preset" =~ ^[bB]$ ]]; then STEP=2; continue; fi

            case "$input_preset" in
                1|ultrafast) PRESET="ultrafast" ;;
                2|fast|"")   PRESET="fast" ;;
                3|medium)    PRESET="medium" ;;
                4|slow)      PRESET="slow" ;;
                *)           PRESET="$input_preset" ;;
            esac

            STEP=4
            ;;

        4)
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Select Platform Optimization${C_RESET}"
            print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
            print_divider "=" "$C_CYAN"
            echo "  ${C_WHITE}[1]${C_RESET} ${C_WHITE}No${C_RESET}        ${C_GRAY}(Keep original fps & rate) [Default]${C_RESET}"
            echo "  ${C_WHITE}[2]${C_RESET} ${C_GREEN}TikTok${C_RESET}    ${C_GRAY}(60fps CFR, 16M cap, AAC 48k)${C_RESET}"
            echo "  ${C_WHITE}[3]${C_RESET} ${C_GREEN}Instagram${C_RESET} ${C_GRAY}(30fps CFR, 14M cap, AAC 48k)${C_RESET}"
            printf "${C_CYAN}Enter choice ${C_WHITE}[1-3]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}1${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_opt

            if [[ "$input_opt" =~ ^[bB]$ ]]; then STEP=3; continue; fi

            case "$input_opt" in
                2|tiktok|TikTok)
                    PLATFORM="tiktok"
                    ;;
                3|insta|instagram|Instagram)
                    PLATFORM="instagram"
                    ;;
                *)
                    PLATFORM="none"
                    ;;
            esac

            STEP=5
            ;;

        5)
            echo ""
            print_divider "=" "$C_CYAN"
            print_center "${C_BOLD}${C_CYAN}Metadata Cleaning${C_RESET}"
            print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
            print_divider "=" "$C_CYAN"
            printf "${C_WHITE}Strip old/unwanted metadata?${C_RESET} ${C_GRAY}[y/N]${C_RESET} ${C_GRAY}(Default: ${C_YELLOW}N${C_GRAY})${C_CYAN}:${C_RESET} "
            read -r input_strip

            if [[ "$input_strip" =~ ^[bB]$ ]]; then STEP=4; continue; fi

            if [[ "$input_strip" =~ ^[yY]$ ]]; then
                META_ARGS="-map_metadata -1"
                META_STATUS="${C_ALERT}Stripped${C_RESET}"
            else
                META_ARGS=""
                META_STATUS="${C_GREEN}Preserved${C_RESET}"
            fi

            break
            ;;
    esac
done

BASE_NAME="output_HDR10"
OUTPUT="$OUTPUT_DIR/${BASE_NAME}.mp4"
COUNT=1

while [ -f "$OUTPUT" ]; do
    OUTPUT="$OUTPUT_DIR/${BASE_NAME}_${COUNT}.mp4"
    ((COUNT++))
done

DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)

# Auto-detect existing color metadata or safely fall back to standard bt709
in_pri=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_primaries -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
in_trc=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_transfer -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
in_spc=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)

if [ -z "$in_pri" ] || [ "$in_pri" = "unknown" ] || [ "$in_pri" = "reserved" ]; then in_pri="bt709"; fi
if [ -z "$in_trc" ] || [ "$in_trc" = "unknown" ] || [ "$in_trc" = "reserved" ]; then in_trc="bt709"; fi
if [ -z "$in_spc" ] || [ "$in_spc" = "unknown" ] || [ "$in_spc" = "reserved" ]; then in_spc="bt709"; fi

VF_BASE="setparams=color_primaries=${in_pri}:color_trc=${in_trc}:colorspace=${in_spc}:range=tv,scale=trunc(iw/2)*2:trunc(ih/2)*2,eq=saturation=${SATURATION},zscale=min=${in_spc}:pin=${in_pri}:tin=${in_trc}:rin=tv:r=full:d=none,format=gbrpf32le,exposure=${EXPOSURE},zscale=pin=${in_pri}:tin=${in_trc}:primaries=bt2020:transfer=smpte2084:matrix=bt2020nc:npl=203,format=yuv420p10le"

if [ "$PLATFORM" = "tiktok" ]; then
    VF_FILTER="fps=60,${VF_BASE}"
    AUDIO_ARGS="-c:a aac -b:a 192k -ar 48000"
    RATE_ARGS="-maxrate 16M -bufsize 32M"
    if [ -n "$DUR" ] && [ "$DUR" != "N/A" ]; then
        TOTAL_FRAMES=$(awk -v d="$DUR" 'BEGIN {printf "%.0f", d * 60}')
    fi
elif [ "$PLATFORM" = "instagram" ]; then
    VF_FILTER="fps=30,${VF_BASE}"
    AUDIO_ARGS="-c:a aac -b:a 192k -ar 48000"
    RATE_ARGS="-maxrate 14M -bufsize 28M"
    if [ -n "$DUR" ] && [ "$DUR" != "N/A" ]; then
        TOTAL_FRAMES=$(awk -v d="$DUR" 'BEGIN {printf "%.0f", d * 30}')
    fi
else
    VF_FILTER="${VF_BASE}"
    AUDIO_ARGS="-c:a copy"
    RATE_ARGS=""
    TOTAL_FRAMES=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
    if [ -z "$TOTAL_FRAMES" ] || [ "$TOTAL_FRAMES" = "N/A" ] || [ "$TOTAL_FRAMES" -le 0 ] 2>/dev/null; then
        r_fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        if [ -n "$DUR" ] && [ "$DUR" != "N/A" ] && [ -n "$r_fps" ]; then
            TOTAL_FRAMES=$(awk -v d="$DUR" -v fps="$r_fps" 'BEGIN {
                split(fps, a, "/");
                val = (length(a) > 1 && a[2] > 0) ? a[1]/a[2] : a[1];
                printf "%.0f", d * val;
            }')
        fi
    fi
fi

TOTAL_FRAMES=${TOTAL_FRAMES:-0}

echo ""
print_divider "=" "$C_CYAN"
echo "${C_BOLD}${C_WHITE}Selected :${C_RESET} ${C_GREEN}$(basename "$INPUT_FILE")${C_RESET}"
echo "${C_BOLD}${C_WHITE}Output   :${C_RESET} ${C_GREEN}$(basename "$OUTPUT")${C_RESET}"
echo "${C_BOLD}${C_WHITE}Target   :${C_RESET} ${C_YELLOW}$PLATFORM${C_RESET} ${C_CYAN}|${C_RESET} ${C_BOLD}${C_WHITE}Meta:${C_RESET} $META_STATUS"
echo "${C_BOLD}${C_WHITE}Grading  :${C_RESET} ${C_CYAN}Exp: ${C_YELLOW}$EXPOSURE${C_RESET} ${C_CYAN}|${C_RESET} ${C_CYAN}High: ${C_YELLOW}${HIGHLIGHT}nits${C_RESET} ${C_CYAN}|${C_RESET} ${C_CYAN}Sat: ${C_YELLOW}$SATURATION${C_RESET}"
print_divider "=" "$C_CYAN"

if ffprobe -v error -select_streams v:0 \
    -show_entries stream=color_transfer,color_primaries,color_space \
    -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null | \
    grep -Eiq 'smpte2084|arib-std-b67'; then
    echo "${C_ALERT}[!] Input video is already HDR. Skipping conversion.${C_RESET}"
    exit 0
fi

termux-wake-lock 2>/dev/null

echo ""
echo "${C_BOLD}${C_WHITE}Encoding in progress...${C_RESET} ${C_WHITE}[${C_GREEN}P${C_WHITE}]${C_RESET} Pause ${C_CYAN}|${C_RESET} ${C_WHITE}[${C_ALERT}Q${C_WHITE}]${C_RESET} Stop"

ERR_LOG="$OUTPUT_DIR/.ffmpeg_err.log"
FIFO="$TMP_DIR/sdr2hdr_fifo_$$"
STOP_FLAG="$TMP_DIR/sdr2hdr_stop_$$"
rm -f "$FIFO" "$STOP_FLAG"
mkfifo "$FIFO"

cur_frame=0
cur_fps="0"

ffmpeg -nostdin -hide_banner -loglevel error \
    -i "$INPUT_FILE" \
    -vf "$VF_FILTER" \
    -c:v libx265 \
    -preset "$PRESET" \
    -crf 20 \
    $RATE_ARGS \
    -tag:v hvc1 \
    -color_primaries bt2020 \
    -color_trc smpte2084 \
    -colorspace bt2020nc \
    -x265-params "hdr10=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=${HIGHLIGHT},${HIGHLIGHT}" \
    $AUDIO_ARGS \
    $META_ARGS \
    -movflags +faststart \
    -progress "$FIFO" \
    "$OUTPUT" 2>"$ERR_LOG" &

FFMPEG_PID=$!

control_listener() {
    trap 'stty sane 2>/dev/null; exit 0' TERM INT
    local paused=0
    while kill -0 "$FFMPEG_PID" 2>/dev/null; do
        if read -r -s -n 1 -t 0.5 key < /dev/tty 2>/dev/null; then
            case "$key" in
                p|P)
                    if [ "$paused" -eq 0 ]; then
                        kill -STOP "$FFMPEG_PID" 2>/dev/null
                        paused=1
                        printf "\r\e[K${C_WHITE}[${C_ALERT}⏸ PAUSED${C_WHITE}]${C_RESET} Press ${C_GREEN}'P'${C_RESET} to Resume ${C_CYAN}|${C_RESET} ${C_ALERT}'Q'${C_RESET} to Stop " > /dev/tty
                    else
                        kill -CONT "$FFMPEG_PID" 2>/dev/null
                        paused=0
                    fi
                    ;;
                q|Q)
                    touch "$STOP_FLAG"
                    printf "\r\e[K${C_ALERT}[⏹ STOPPING...]${C_RESET} Cancelling encode...\n" > /dev/tty
                    kill -CONT "$FFMPEG_PID" 2>/dev/null
                    kill -INT "$FFMPEG_PID" 2>/dev/null
                    sleep 0.5
                    kill -9 "$FFMPEG_PID" 2>/dev/null
                    break
                    ;;
            esac
        fi
    done
    stty sane 2>/dev/null
}

control_listener &
LISTENER_PID=$!

while IFS='=' read -r key val; do
    case "$key" in
        frame)
            cur_frame="$val"
            ;;
        fps)
            cur_fps="$val"
            ;;
        progress)
            if [ "$TOTAL_FRAMES" -gt 0 ] 2>/dev/null; then
                pct=$(( cur_frame * 100 / TOTAL_FRAMES ))

                remaining=$(( TOTAL_FRAMES - cur_frame ))
                [ "$remaining" -lt 0 ] && remaining=0

                fps_scaled=0
                if [[ "$cur_fps" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
                    int_p="${BASH_REMATCH[1]}"
                    dec_p="${BASH_REMATCH[2]:0:2}"
                    [ ${#dec_p} -eq 1 ] && dec_p="${dec_p}0"
                    fps_scaled=$(( int_p * 100 + 10#$dec_p ))
                elif [[ "$cur_fps" =~ ^[0-9]+$ ]]; then
                    fps_scaled=$(( cur_fps * 100 ))
                fi

                eta_str="--:--"
                if [ "$fps_scaled" -gt 0 ] && [ "$remaining" -gt 0 ]; then
                    eta_sec=$(( remaining * 100 / fps_scaled ))
                    eta_m=$(( eta_sec / 60 ))
                    eta_s=$(( eta_sec % 60 ))
                    printf -v eta_str "%02d:%02d" "$eta_m" "$eta_s"
                elif [ "$remaining" -eq 0 ]; then
                    eta_str="00:00"
                fi

                if [ "$cur_frame" -gt "$TOTAL_FRAMES" ]; then
                    printf "\r\e[K${C_BOLD}${C_WHITE}Finishing frames:${C_RESET} %d ${C_CYAN}|${C_RESET} ${C_BOLD}${C_WHITE}FPS:${C_RESET} %s" "$cur_frame" "$cur_fps"
                elif [ "$val" = "end" ]; then
                    printf "\r\e[K${C_WHITE}[${C_GREEN}▊▊▊▊▊▊▊▊${C_WHITE}]${C_RESET} ${C_YELLOW}100%%${C_RESET} ${C_CYAN}|${C_RESET} ${C_CYAN}Writing MP4 faststart headers...${C_RESET}"
                else
                    bar_len=8
                    filled=$(( pct * bar_len / 100 ))
                    [ "$filled" -gt 8 ] && filled=8
                    empty=$(( bar_len - filled ))

                    fill_str=""
                    for ((b=0; b<filled; b++)); do fill_str="${fill_str}▊"; done
                    empty_str=""
                    for ((b=0; b<empty; b++)); do empty_str="${empty_str}-"; done

                    printf "\r\e[K${C_WHITE}[${C_GREEN}%s${C_GRAY}%s${C_WHITE}]${C_RESET} ${C_YELLOW}%3d%%${C_RESET} ${C_CYAN}|${C_RESET} ${C_WHITE}%d${C_YELLOW}/${C_WHITE}%d${C_RESET} ${C_CYAN}|${C_RESET} ${C_YELLOW}%s${C_RESET}" "$fill_str" "$empty_str" "$pct" "$cur_frame" "$TOTAL_FRAMES" "$eta_str"
                fi
            else
                printf "\r\e[K${C_BOLD}${C_WHITE}Frame:${C_RESET} %d ${C_CYAN}|${C_RESET} ${C_BOLD}${C_WHITE}FPS:${C_RESET} %s" "$cur_frame" "$cur_fps"
            fi
            ;;
    esac
done < "$FIFO"

wait "$FFMPEG_PID" 2>/dev/null
STATUS=$?

kill "$LISTENER_PID" 2>/dev/null
wait "$LISTENER_PID" 2>/dev/null
rm -f "$FIFO"

termux-wake-unlock 2>/dev/null
stty sane 2>/dev/null

if [ -f "$STOP_FLAG" ]; then
    rm -f "$STOP_FLAG" "$OUTPUT" "$ERR_LOG"
    printf "\r\e[K\n"
    print_divider "=" "$C_CYAN"
    print_center "${C_BOLD}${C_ALERT}[!] Conversion stopped by user.${C_RESET}"
    print_divider "=" "$C_CYAN"
    echo ""
    exit 0
fi

if [ $STATUS -eq 0 ]; then
    rm -f "$ERR_LOG"

    printf "\r\e[K\n"
    print_divider "=" "$C_CYAN"
    print_center "${C_BOLD}${C_GREEN}[✓] DONE — saved to DCIM/HDR10_Converted${C_RESET}"
    print_divider "=" "$C_CYAN"
    echo ""

    termux-open "$OUTPUT" 2>/dev/null

    exit 0
else
    printf "\r\e[K\n"
    print_divider "=" "$C_CYAN"
    print_center "${C_BOLD}${C_ALERT}[✗] ERROR: Conversion failed.${C_RESET}"
    if [ -s "$ERR_LOG" ]; then
        echo "${C_WHITE}Reason:${C_RESET}"
        cat "$ERR_LOG"
    fi
    print_divider "=" "$C_CYAN"
    rm -f "$OUTPUT" "$ERR_LOG"
    exit 1
fi
EOF

chmod +x ~/sdr2hdr.sh
bash ~/sdr2hdr.sh