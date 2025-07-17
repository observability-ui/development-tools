#!/bin/bash

# Questions, options, and answers
question=(
    "Which data model do you want to configure?"
)
options=(
    "a) otel b) viaQ"
)

score=0
num_questions=${#question[@]}

# Loop for asking just the first question
for i in 0; do
    echo
    echo "${question[$i]}"
    echo "${options[$i]}"

    while true; do
        read -p "Enter your choice (a or b): " choice
        case $choice in
        a | b)
            break
            ;;
        *)
            echo "Invalid input. Please enter a or b."
            ;;
        esac
    done

    # Translate choice to index (1 for 'a' or 2 for 'b')
    choice_index=$(($(echo "$choice" | tr 'ab' '12') - 0))

    if [ "$choice_index" -eq 1 ]; then
        ./deploy.sh "otel"
    else
        ./deploy.sh "viaq"
    fi
done

exit 0
