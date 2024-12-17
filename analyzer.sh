#!/bin/env bash
readonly SCRIPT_DIR=$(cd $(dirname $0); pwd)

############### 定数定義 #########################
# タイムゾーン
export TZ="Asia/Tokyo"
# 出力ログファイル
readonly OUTPUT_LOG_FILE="out.csv"
# ログの時刻フォーマット
readonly DATE_FORMAT="%Y-%m-%d %H:%M:%S"
##################################################

# git show --shortstat の出力を解析して情報を抽出する
# @param commit_id コミットID
# @return ファイル変更数 追加行数 削除行数
function diff_shortstats_by_commit_id() {
    local -r _commit_id=$1

    # commitの差分を取得
    local -r _diff_output=$(git show --shortstat "${_commit_id}" | grep -oP "(\d+)\sfile|(\d+)\sinsertion|(\d+)\sdeletion")

    # ファイル変更数を取得
    _files=$(grep -oP '(\d+)\sfile' <<< "${_diff_output}" | grep -oP '\d+')
    # 行の追加数を取得
    _additions=$(grep -oP '(\d+)\sinsertion' <<< "${_diff_output}" | grep -oP '\d+')
    # 行の削除数を取得
    _deletions=$(grep -oP '(\d+)\sdeletion' <<< "${_diff_output}" | grep -oP '\d+')

    echo "${_files:-0} ${_additions:-0} ${_deletions:-0}"
}

# コミットIDからコミットタイプを取得
# @param commit_id コミットID
# @return コミットタイプ
function commit_type_by_commit_id() {
    local -r _commit_id=$1

    local -r _merge_commit=$(git log --pretty=format:'%H' --merges)
    if [[ ${_merge_commit} =~ ${_commit_id} ]]; then
        echo "Merge"
    else
        echo "Normal"
    fi
}

# コミットログの解析
# @param _group_id 班番号
# @param _repo_url リポジトリのURL
# @return 解析結果
function analysis_commit_history() {
    local -r _group_id=$1
    local -r _repo_url=$2

    local -r _repository_dir="${SCRIPT_DIR}/tmp_repo"
    if [ -d "${_repository_dir}" ]; then
        rm -rf "${_repository_dir}"
    fi

    git clone -q "${_repo_url}" "${_repository_dir}"
    cd "${_repository_dir}"

    # ログを整形して変数に格納(commit_id,author_name,author_email,date,commit_message)
    local -r _commit_log=$(git log --pretty=format:'%H,%an,%ae,%ad,"%s"' --date=format:"${DATE_FORMAT}")

    local  _commit_id _author _email _data _message
    local _repo_name
    local _files _additions _deletions
    local _commit_type

    # ログをもとに追加情報を取得する
    while IFS=',' read -r _commit_id _author _email _date _message; do

        # リポジトリ名を取得
        repo_name=$(basename "${_repo_url}" .git)
        # 変更ファイル情報を取得
        read -r _files _additions _deletions <<< $(diff_shortstats_by_commit_id "${_commit_id}")
        # マージコミットかどうか
        _commit_type=$(commit_type_by_commit_id "${_commit_id}")

        # 情報をまとめて出力
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "${_group_id}" "${repo_name}" "${_repo_url}" "${_commit_id}" "${_author}" "${_email}" "${_date}" "${_message}" "${_files}" "${_additions}" "${_deletions}" "${_commit_type}"
    done <<< "${_commit_log}"

    # リポジトリの削除
    cd "${SCRIPT_DIR}"
    rm -rf "${_repository_dir}"
}

# メイン処理
function main() {
    local _is_overwrite=false

    # 引数処理
    while getopts "hf" opt
    do
        case $opt in
            h)
                echo "Usage: $0 [-hf] REPO_LIST_FILE"
                exit 0
                ;;
            f)
                _is_overwrite=true
                ;;
            \?)
                echo "Usage: $0 [-hf] REPO_LIST_FILE"
                exit 1
                ;;
        esac
    done

    # オプション分をシフト
    shift $((OPTIND - 1))

    # 引数がない場合は終了
    if [ $# -ne 1 ]; then
        echo "Usage: $0 [-hf] REPO_LIST_FILE"
        exit 1
    fi

    local -r _repo_list_file=$1

    # リポジトリリストファイルが存在しない場合は終了
    if [ ! -f "${_repo_list_file}" ]; then
        echo "File not found: ${_repo_list_file}"
        exit 1
    fi

    # 出力ファイルが存在する場合は確認
    if [ -f "${OUTPUT_LOG_FILE}" ] && [ "${_is_overwrite}" = false ] ; then
        local _answer
        read -p "Output file already exists. Overwrite? [y/N]: " _answer

        if [[ ! "${_answer}" =~ ^[yY]$ ]]; then
            exit 0
        fi

    fi

    # csvヘッダー
    echo "group_id, repo_name, repo_url, commit_id, author_name, author_email, date, message, files, additions, deletions, commit_type" > "${OUTPUT_LOG_FILE}"

    local _group_id _repo_url

    # csvファイルからリポジトリ情報を取得、ログを整形してcsvとして出力
    while IFS=',' read -r _group_id _repo_url; do
        echo "Processing repository: ${_repo_url}"

        # csv出力
        analysis_commit_history ${_group_id} ${_repo_url} >> ${OUTPUT_LOG_FILE}
    done < "${_repo_list_file}"
}

main "$@"
