#!/bin/bash

if [ -z "$1" ]; then
	echo "$0 <project-path>"
	exit 1
fi
path=$1
if [ "$path" == "." ]; then
	path=$(pwd)
fi
project_id=$(jq -r ".\"$(pwd)\"".id < ~/.ccinsights/projects.json)
jq -s '{
  perModel: (
    [ .[] | .modelUsage[] ]
    | group_by(.modelName)
    | map({
        modelName: .[0].modelName,
        totalCostUsd: (map(.costUsd) | add)
      })
  ),
  overallTotalUsd: (
    [ .[] | .modelUsage[].costUsd ] | add
  )
}' ~/.ccinsights/projects/$project_id/tracking.jsonl
