#!/data/data/com.termux/files/usr/bin/bash

OUTPUT_DIR="/sdcard/DCIM/HDR10_Converted"
TMP_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

mkdir -p "$OUTPUT_DIR" "$TMP_DIR"
rm -f "$OUTPUT_DIR/.nomedia"

# 24-bit TrueColor Palette
C_RESET=$'\e[0m'
C_BOLD=$'\e[1m'
C_CYAN=$'\e[38;2;56;189;248m'
C_YELLOW=$'\e[38;2;250;204;21m'
C_GREEN=$'\e[38;2;74;222;128m'
C_WHITE=$'\e[38;2;248;250;252m'
C_GRAY=$'\e[38;2;148;163;184m'
C_ALERT=$'\e[38;2;244;63;94m'
C_VRED=$'\e[38;2;255;49;49m'

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
    [[ -z "$w" || "$w" -le 0 ]] && w="${COLUMNS:-42}"
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

# -------------------------------------------------------------
# CLI / Non-Interactive Route (Used by Python UI or fast runs)
# Arguments: input_file exposure highlight saturation preset platform
# -------------------------------------------------------------
if [ -f "$1" ] && [ -n "$2" ]; then
    INPUT_FILE="$1"
    EXPOSURE="${2:-0.25}"
    HIGHLIGHT="${3:-240}"
    SATURATION="${4:-1.25}"
    PRESET="${5:-faster}"
    PLATFORM="${6:-none}"
    META_ARGS=""
    META_STATUS="${C_GREEN}Preserved${C_RESET}"
    IS_INTERACTIVE=0
else
    IS_INTERACTIVE=1
    STEP=0
    if [ -n "$1" ]; then
        if [ -f "$1" ]; then
            INPUT_FILE="$1"
            STEP=2
        elif [ -d "$1" ]; then
            SELECTED_DIR="$1"
            STEP=1
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
                        [ "$grp" = "$sub" ] && sub="(Root Folder)"
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
                [[ "$fchoice" =~ ^[qQ]$ ]] && exit 0
                if [[ "$fchoice" =~ ^[mM]$ ]]; then
                    printf "${C_CYAN}Enter full directory path: ${C_RESET}"
                    read -r custom_dir
                    [ -d "$custom_dir" ] && { SELECTED_DIR="$custom_dir"; STEP=1; }
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
                    [[ "$base" != trashed-* && "$base" != output_HDR10* ]] && video_list+=("$f")
                done

                if [ ${#video_list[@]} -eq 0 ]; then
                    echo "${C_ALERT}[✗] No valid videos found.${C_RESET}"
                    STEP=0; continue
                fi

                disp_folder="${SELECTED_DIR#/sdcard/}"
                echo ""
                print_divider "=" "$C_CYAN"
                print_center "${C_BOLD}${C_CYAN}Select a Video to Convert${C_RESET}"
                print_center "${C_VRED}(type 'b' to go back)${C_RESET}"
                print_divider "=" "$C_CYAN"
                for i in "${!video_list[@]}"; do
                    f="${video_list[$i]}"
                    meta=$(get_video_meta "$f")
                    printf "  ${C_WHITE}[%d]${C_RESET} ${C_BOLD}${C_WHITE}%s${C_RESET}\n      ${C_CYAN}└─${C_RESET} %b\n" "$((i + 1))" "$(basename "$f")" "$meta"
                done
                printf "${C_CYAN}Enter number ${C_WHITE}(1-%d)${C_CYAN} or ${C_ALERT}[q]${C_CYAN}uit:${C_RESET} " "${#video_list[@]}"
                read -r choice
                [[ "$choice" =~ ^[qQ]$ ]] && exit 0
                [[ "$choice" =~ ^[bB]$ ]] && { STEP=0; continue; }

                INPUT_FILE="${video_list[$((choice - 1))]}"
                STEP=2
                ;;

            2)
                echo ""
                print_divider "=" "$C_CYAN"
                print_center "${C_BOLD}${C_CYAN}Adjust Grading Settings${C_RESET}"
                print_divider "=" "$C_CYAN"
                printf "${C_WHITE}Exposure${C_RESET} ${C_GRAY}(Default: 0.25):${C_RESET} "
                read -r input_exp
                [[ "$input_exp" =~ ^[bB]$ ]] && { STEP=1; continue; }
                EXPOSURE="${input_exp:-0.25}"

                printf "${C_WHITE}Highlight (MaxCLL)${C_RESET} ${C_GRAY}(Default: 240):${C_RESET} "
                read -r input_hl
                [[ "$input_hl" =~ ^[bB]$ ]] && { STEP=1; continue; }
                HIGHLIGHT="${input_hl:-240}"

                printf "${C_WHITE}Saturation${C_RESET} ${C_GRAY}(Default: 1.25):${C_RESET} "
                read -r input_sat
                [[ "$input_sat" =~ ^[bB]$ ]] && { STEP=1; continue; }
                SATURATION="${input_sat:-1.25}"
                STEP=3
                ;;

            3)
                echo ""
                print_divider "=" "$C_CYAN"
                print_center "${C_BOLD}${C_CYAN}Select Preset${C_RESET}"
                print_divider "=" "$C_CYAN"
                echo "  [1] ultrafast  [2] faster (Default)  [3] medium  [4] slow"
                printf "${C_CYAN}Choice [1-4]:${C_RESET} "
                read -r input_preset
                [[ "$input_preset" =~ ^[bB]$ ]] && { STEP=2; continue; }
                case "$input_preset" in
                    1|ultrafast) PRESET="ultrafast" ;;
                    2|faster|"") PRESET="faster" ;;
                    3|medium)    PRESET="medium" ;;
                    4|slow)      PRESET="slow" ;;
                    *)           PRESET="$input_preset" ;;
                esac
                STEP=4
                ;;

            4)
                echo ""
                print_divider "=" "$C_CYAN"
                print_center "${C_BOLD}${C_CYAN}Select Platform${C_RESET}"
                print_divider "=" "$C_CYAN"
                echo "  [1] No (Original)  [2] TikTok (60fps)  [3] Instagram (30fps)"
                printf "${C_CYAN}Choice [1-3]:${C_RESET} "
                read -r input_opt
                [[ "$input_opt" =~ ^[bB]$ ]] && { STEP=3; continue; }
                case "$input_opt" in
                    2) PLATFORM="tiktok" ;;
                    3) PLATFORM="instagram" ;;
                    *) PLATFORM="none" ;;
                esac
                STEP=5
                ;;

            5)
                printf "${C_WHITE}Strip old metadata? [y/N]:${C_RESET} "
                read -r input_strip
                [[ "$input_strip" =~ ^[bB]$ ]] && { STEP=4; continue; }
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
fi

BASE_NAME="output_HDR10"
OUTPUT="$OUTPUT_DIR/${BASE_NAME}.mp4"
COUNT=1
while [ -f "$OUTPUT" ]; do
    OUTPUT="$OUTPUT_DIR/${BASE_NAME}_${COUNT}.mp4"
    ((COUNT++))
done

# Instant Container Header Extraction
DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
in_pri=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_primaries -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
in_trc=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_transfer -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
in_spc=$(ffprobe -v error -select_streams v:0 -show_entries stream=color_space -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)

[ -z "$in_pri" ] || [ "$in_pri" = "unknown" ] || [ "$in_pri" = "reserved" ] && in_pri="bt709"
[ -z "$in_trc" ] || [ "$in_trc" = "unknown" ] || [ "$in_trc" = "reserved" ] && in_trc="bt709"
[ -z "$in_spc" ] || [ "$in_spc" = "unknown" ] || [ "$in_spc" = "reserved" ] && in_spc="bt709"

VF_BASE="setparams=color_primaries=${in_pri}:color_trc=${in_trc}:colorspace=${in_spc}:range=tv,scale=trunc(iw/2)*2:trunc(ih/2)*2,eq=saturation=${SATURATION},zscale=min=${in_spc}:pin=${in_pri}:tin=${in_trc}:rin=tv:r=full:d=none,format=gbrpf32le,exposure=${EXPOSURE},zscale=pin=${in_pri}:tin=${in_trc}:primaries=bt2020:transfer=smpte2084:matrix=bt2020nc:npl=203,format=yuv420p10le"

if [ "$PLATFORM" = "tiktok" ]; then
    VF_FILTER="fps=60,${VF_BASE}"
    AUDIO_ARGS="-c:a aac -b:a 192k -ar 48000"
    RATE_ARGS="-maxrate 16M -bufsize 32M"
    TOTAL_FRAMES=$(awk -v d="$DUR" 'BEGIN {printf "%.0f", d * 60}')
elif [ "$PLATFORM" = "instagram" ]; then
    VF_FILTER="fps=30,${VF_BASE}"
    AUDIO_ARGS="-c:a aac -b:a 192k -ar 48000"
    RATE_ARGS="-maxrate 14M -bufsize 28M"
    TOTAL_FRAMES=$(awk -v d="$DUR" 'BEGIN {printf "%.0f", d * 30}')
else
    VF_FILTER="${VF_BASE}"
    AUDIO_ARGS="-c:a copy"
    RATE_ARGS=""
    TOTAL_FRAMES=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
    if [ -z "$TOTAL_FRAMES" ] || [ "$TOTAL_FRAMES" = "N/A" ] || [ "$TOTAL_FRAMES" -le 0 ] 2>/dev/null; then
        r_fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        if [ -n "$DUR" ] && [ -n "$r_fps" ]; then
            TOTAL_FRAMES=$(awk -v d="$DUR" -v fps="$r_fps" 'BEGIN {
                split(fps, a, "/");
                val = (length(a) > 1 && a[2] > 0) ? a[1]/a[2] : a[1];
                printf "%.0f", d * val;
            }')
        fi
    fi
fi
TOTAL_FRAMES=${TOTAL_FRAMES:-0}

termux-wake-lock 2>/dev/null
ERR_LOG="$OUTPUT_DIR/.ffmpeg_err.log"
FIFO="$TMP_DIR/sdr2hdr_fifo_$$"
STOP_FLAG="$TMP_DIR/sdr2hdr_stop_$$"
rm -f "$FIFO" "$STOP_FLAG"
mkfifo "$FIFO"

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

# Interactive key listener only runs if in a real TTY terminal
if [ "$IS_INTERACTIVE" -eq 1 ] && [ -t 0 ]; then
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
                            printf "\r\e[K${C_WHITE}[${C_ALERT}⏸ PAUSED${C_WHITE}]${C_RESET} Press ${C_GREEN}'P'${C_RESET} to Resume " > /dev/tty
                        else
                            kill -CONT "$FFMPEG_PID" 2>/dev/null
                            paused=0
                        fi
                        ;;
                    q|Q)
                        touch "$STOP_FLAG"
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
fi

cur_frame=0
cur_fps="0"

while IFS='=' read -r key val; do
    case "$key" in
        frame) cur_frame="$val" ;;
        fps) cur_fps="$val" ;;
        progress)
            if [ "$TOTAL_FRAMES" -gt 0 ] 2>/dev/null; then
                pct=$(( cur_frame * 100 / TOTAL_FRAMES ))
                printf "\r\e[K${C_WHITE}[${C_GREEN}%d%%${C_WHITE}]${C_RESET} Frame: %d/%d | FPS: %s" "$pct" "$cur_frame" "$TOTAL_FRAMES" "$cur_fps"
            else
                printf "\r\e[KFrame: %d | FPS: %s" "$cur_frame" "$cur_fps"
            fi
            ;;
    esac
done < "$FIFO"

wait "$FFMPEG_PID" 2>/dev/null
STATUS=$?

[ -n "$LISTENER_PID" ] && kill "$LISTENER_PID" 2>/dev/null
rm -f "$FIFO"
termux-wake-unlock 2>/dev/null
stty sane 2>/dev/null

if [ $STATUS -eq 0 ]; then
    am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$OUTPUT" > /dev/null 2>&1
    echo -e "\n${C_GREEN}[✓] DONE — saved to $OUTPUT${C_RESET}"
    exit 0
else
    echo -e "\n${C_ALERT}[✗] ERROR: Conversion failed.${C_RESET}"
    [ -s "$ERR_LOG" ] && cat "$ERR_LOG"
    rm -f "$OUTPUT"
    exit 1
fi
