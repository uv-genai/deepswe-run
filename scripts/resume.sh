#!/usr/bin/env bash
# Usage: ./scripts/resume.sh <job-dir>      (relative to repo root, e.g. jobs/<job-name>)
JOB="${1:?usage: resume.sh <job-dir>}"
cd "$(dirname "$0")/.."          # repo root
mkdir -p log
export OPENAI_API_BASE=http://172.17.0.1/v1
export OPENAI_BASE_URL=http://172.17.0.1/v1
export OPENAI_API_KEY=sk-local
nohup pier job resume -p "$JOB" >log/resume.log 2>&1 &
