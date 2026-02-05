#!/bin/sh
jq -r ".\"$(pwd)\"".id < ~/.ccinsights/projects.json
