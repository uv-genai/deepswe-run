#!/usr/bin/env bash
export OPENAI_API_BASE=http://172.17.0.1/v1
export OPENAI_BASE_URL=http://172.17.0.1/v1
export OPENAI_API_KEY=sk-local
nohup pier job resume -p jobs/deepswe-gufo-qwen3.8-flash-next-tp2-q8 >resume.log 2>&1 &
