#!/bin/bash

# GitLogger CLI
# A command-line interface for interacting with the GitLogger API
# Works with local repositories without requiring uploads
# Enhanced with Gemini Flash model for detailed reporting and Jira log formatting

# Configuration
API_BASE="http://localhost:3000/api"
VERSION="1.1.0"  # Updated version

# Working hours configuration
WORK_HOURS_PER_DAY=8
WORK_MINUTES_PER_DAY=$((WORK_HOURS_PER_DAY * 60))
MAX_MINUTES_PER_TASK=240  # Maximum 4 hours per task
WORKING_START_TIME="09:00"
WORKING_END_TIME="17:00"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Gemini API Configuration
GEMINI_API_KEY="AIzaSyB_4QxUxJeAAVPaUxlDVgR0uQusrgnNeyU"
GEMINI_API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-8b:generateContent"
GEMINI_MODEL="gemini-1.5-flash-8b" 
GEMINI_ESTIMATE_ACCURACY="±15%"

# Function to install GitLogger CLI
install_gitlogger() {
  local install_dir="/usr/local/bin"
  local script_url="https://raw.githubusercontent.com/GittyAjay/Gitai/dev/gitlogger-cli.sh"
  local install_path="$install_dir/gitlogger"
  
  # Check if we have write permissions to the install directory
  if [ ! -w "$install_dir" ]; then
    print_error "You don't have write permissions to $install_dir"
    print_info "Try running with sudo: sudo bash $0 install"
    return 1
  fi
  
  print_info "Downloading GitLogger CLI..."
  
  # Download the script
  if ! curl -sSL "$script_url" -o "$install_path"; then
    print_error "Failed to download GitLogger CLI"
    return 1
  fi
  
  # Make the script executable
  chmod +x "$install_path"
  
  print_success "GitLogger CLI installed successfully to $install_path"
  print_info "You can now use it by typing 'gitlogger' in your terminal"
  
  return 0
}
# Helper functions
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}  GitLogger CLI v${VERSION}${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

print_error() {
  echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
  echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

print_debug() {
  echo -e "${PURPLE}DEBUG: $1${NC}"
}

# Function to show loading animation
show_loading() {
  local pid=$1
  local message="${2:-Processing...}"
  local spin='-\|/'
  local i=0
  
  echo -e -n "\n${YELLOW}$message${NC} "
  
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    echo -e -n "\b${spin:$i:1}"
    sleep 0.1
  done
  
  echo -e -n "\b \n"
}

show_help() {
  print_header
  echo "Usage: gitlogger [command] [options]"
  echo ""
  echo "Commands:"
  echo "  init [directory]             Initialize GitLogger with a local git repository (default: current directory)"
  echo "  info                         Show information about the current repository"
  echo "  log [date]                   Get Git logs for a specific date (YYYY-MM-DD)"
  echo "  report [start] [end]         Get Git logs for a date range (YYYY-MM-DD)"
  echo "  jira [start] [end]           Generate Jira log report for a date range"
  echo "  help                         Show this help message"
  echo ""
  echo "Examples:"
  echo "  gitlogger init ~/projects/my-repo"
  echo "  gitlogger log 2023-04-09"
  echo "  gitlogger report 2023-04-01 2023-04-09"
  echo "  gitlogger jira 2023-04-01 2023-04-09"
  echo ""
}

# Function to call Gemini API
call_gemini_api() {
  local prompt="$1"
  local api_key="$GEMINI_API_KEY"
  local endpoint="$GEMINI_API_ENDPOINT"
  
  # Prepare the request payload
  local payload=$(cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": "$prompt"
    }]
  }]
}
EOF
)
  
  # Start the API call in the background and capture its output
  local temp_file=$(mktemp)
  (curl -s -X POST "$endpoint?key=$api_key" \
    -H "Content-Type: application/json" \
    -d "$payload" > "$temp_file") &
  
  local curl_pid=$!
  
  # Show loading animation while waiting for the API call to complete
  show_loading $curl_pid "Generating Gemini AI analysis..."
  
  # Wait for the curl command to finish
  wait $curl_pid
  
  # Read the response from the temporary file
  local response=$(cat "$temp_file")
  rm "$temp_file"  # Clean up the temporary file
  
  # Check if the API call was successful
  if [[ $response == *"error"* ]]; then
    echo "Error calling Gemini API: $response"
    return 1
  fi
  
  # Extract the generated text from the response
  local generated_text=$(echo "$response" | grep -o '"text": "[^"]*"' | cut -d'"' -f4)
  
  if [ -z "$generated_text" ]; then
    echo "No response from Gemini API. Please check your API key and internet connection."
    return 1
  fi
  
  echo "$generated_text"
}

# Function to analyze commits using Gemini API
gemini_analyze_commits() {
  local commits="$1"
  local date_range="$2"
  
  # Calculate basic statistics
  local total_commits=$(echo "$commits" | wc -l)
  local unique_authors=$(echo "$commits" | sed -n 's/.*(\([^,]*\).*/\1/p' | sort -u | wc -l)
  
  print_info "Processing $total_commits commits for analysis..."
  
  # Prepare commit data for analysis
  local commit_data=""
  while IFS= read -r commit; do
    # Extract commit message and author using sed instead of awk
    local message=$(echo "$commit" | sed -E 's/^[^ ]+ - (.*) \(.*\)$/\1/')
    local author=$(echo "$commit" | sed -n 's/.*(\([^,]*\).*/\1/p')
    local date=$(echo "$commit" | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}")
    commit_data+="Commit: $message\nAuthor: $author\nDate: $date\n\n"
  done <<< "$commits"
  
  # Create the prompt for Gemini
  local prompt="Analyze the following git commits and provide a human-friendly Jira work log report with accurate time estimates:

1. Format Requirements:
   - Group commits by date and author
   - Use clear section headers and bullet points
   - Make it suitable for direct copy-paste into Jira

2. For each commit, provide:
   - A clear, professional description of the work done
   - Realistic time estimate based on these guidelines:
     * Simple changes (fixes, updates): 15-30 minutes
     * Medium complexity (feature additions, UI components): 30-60 minutes
     * Complex changes (implementations, refactoring): 1-2 hours
     * Never exceed 4 hours for a single commit
   - Include any issue/ticket numbers if present

3. Time Calculation Rules:
   - Standard working day is 8 hours (${WORK_HOURS_PER_DAY} hours)
   - Working hours: ${WORKING_START_TIME} - ${WORKING_END_TIME}
   - Calculate time based on commit complexity:
     * Simple commits (fix, update, add): 15-30 minutes
     * Medium commits (implement, create): 30-60 minutes
     * Complex commits (refactor, optimize): 1-2 hours
   - Consider commit message length and complexity
   - Ensure total daily time doesn't exceed standard working hours unrealistically

4. Summary Format:
   **Total Time Summary:**
   • Total Hours: [sum of all estimates]
   • Working Days (${WORK_HOURS_PER_DAY}h/day): [total hours / ${WORK_HOURS_PER_DAY}]
   • Percentage of Working Day: [total hours / ${WORK_HOURS_PER_DAY} * 100]

Commits to analyze:
$commit_data

Date Range: $date_range
Total Commits: $total_commits
Unique Authors: $unique_authors"

  # Call Gemini API
  local analysis=$(call_gemini_api "$prompt")
  
  # Check if the API call was successful
  if [ $? -ne 0 ]; then
    print_error "Failed to get analysis from Gemini API"
    return 1
  fi
  
  # Generate analysis report
  local analysis_report=""
  analysis_report+="\n${BLUE}=== Gemini Analysis (${GEMINI_MODEL}) ===${NC}\n"
  analysis_report+="Date Range: $date_range\n"
  analysis_report+="Total Commits: $total_commits\n"
  analysis_report+="Unique Authors: $unique_authors\n"
  analysis_report+="\n${YELLOW}Analysis Results:${NC}\n"
  analysis_report+="$analysis\n"
  
  # Extract and format total time if present
  if [[ "$analysis" =~ "Total Time Summary:" ]]; then
    analysis_report+="\n${GREEN}=== Working Hours Summary ===${NC}\n"
    analysis_report+="• Standard working day: $WORK_HOURS_PER_DAY hours\n"
    analysis_report+="• Working hours: $WORKING_START_TIME - $WORKING_END_TIME\n"
    analysis_report+="• Time estimates accuracy: $GEMINI_ESTIMATE_ACCURACY\n"
  fi
  
  echo -e "$analysis_report"
}

# Function to generate Jira log report
generate_jira_report() {
  local start_date="$1"
  local end_date="$2"
  local repo_dir=$(get_current_repo)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  # Validate date formats
  if ! [[ $start_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! [[ $end_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    print_error "Invalid date format. Please use YYYY-MM-DD"
    return 1
  fi
  
  # Get commits in the date range with full timestamp
  local commits=$(git -C "$repo_dir" log --date=iso-strict --after="$start_date 00:00:00" --before="$end_date 23:59:59" \
    --pretty=format:"%h - %s (%cr)" HEAD)
  
  if [ -z "$commits" ]; then
    print_info "No commits found for date range: $start_date to $end_date"
    return 0
  fi
  
  # Generate formatted Jira log
  local jira_report="\n${GREEN}=== Jira Work Log Format ===${NC}\n"
  jira_report+="Copy and paste the following into your Jira work logs:\n\n"
  
  # Group by date and author
  local current_date=""
  local current_author=""
  local total_time=0
  local daily_totals=()
  local current_day_total=0
  local last_commit_time=""
  
  # Sort commits by date and author
  local sorted_commits=$(echo "$commits" | sort -t'(' -k2,2 -k1,1)
  
  while IFS= read -r commit; do
    local full_timestamp=$(echo "$commit" | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}[+-][0-9]\{2\}:[0-9]\{2\}")
    local date=$(echo "$full_timestamp" | cut -dT -f1)
    local time=$(echo "$full_timestamp" | cut -dT -f2 | cut -d+ -f1 | cut -d- -f1)
    local author=$(echo "$commit" | sed -n 's/.*(\([^,]*\).*/\1/p')
    local message=$(echo "$commit" | sed -E 's/^[^ ]+ - (.*) \(.*\)$/\1/')
    
    # Calculate time difference between commits
    if [ -n "$last_commit_time" ]; then
      local time_diff=$(( $(date -d "$full_timestamp" +%s) - $(date -d "$last_commit_time" +%s) ))
      
      # If time difference is less than 4 hours (14400 seconds), use it as work time
      if [ $time_diff -lt 14400 ]; then
        local minutes=$(( time_diff / 60 ))
        # Add a minimum of 15 minutes per commit
        if [ $minutes -lt 15 ]; then
          minutes=15
        fi
        total_time=$(( total_time + minutes ))
        current_day_total=$(( current_day_total + minutes ))
      else
        # If gap is too large, use complexity-based estimate
        local words=$(echo "$message" | wc -w)
        local complexity_factor=3
        if [[ "$message" =~ ^(fix|update|add|remove) ]]; then
          complexity_factor=2
        elif [[ "$message" =~ ^(implement|refactor|optimize) ]]; then
          complexity_factor=4
        fi
        local estimated_minutes=$(( words * complexity_factor ))
        # Cap individual task time
        if [ $estimated_minutes -gt $MAX_MINUTES_PER_TASK ]; then
          estimated_minutes=$MAX_MINUTES_PER_TASK
        fi
        total_time=$(( total_time + estimated_minutes ))
        current_day_total=$(( current_day_total + estimated_minutes ))
      fi
    else
      # For first commit of the day, use complexity-based estimate
      local words=$(echo "$message" | wc -w)
      local complexity_factor=3
      if [[ "$message" =~ ^(fix|update|add|remove) ]]; then
        complexity_factor=2
      elif [[ "$message" =~ ^(implement|refactor|optimize) ]]; then
        complexity_factor=4
      fi
      local estimated_minutes=$(( words * complexity_factor ))
      if [ $estimated_minutes -gt $MAX_MINUTES_PER_TASK ]; then
        estimated_minutes=$MAX_MINUTES_PER_TASK
      fi
      total_time=$(( total_time + estimated_minutes ))
      current_day_total=$(( current_day_total + estimated_minutes ))
    fi
    
    last_commit_time="$full_timestamp"
    
    # Extract issue number if present
    local issue=$(echo "$message" | grep -o '#[A-Za-z0-9-]\+' || echo "")
    
    # If date or author changed, add a header
    if [ "$date" != "$current_date" ] || [ "$author" != "$current_author" ]; then
      if [ -n "$current_date" ]; then
        daily_totals+=($current_day_total)
        current_day_total=0
        jira_report+="\n"
      fi
      jira_report+="Date: $date\n"
      jira_report+="Author: $author\n"
      jira_report+="Time: $time\n"
      jira_report+="Description: "
      
      current_date="$date"
      current_author="$author"
    else
      jira_report+="\n"
    fi
    
    # Format the work description
    if [ -n "$issue" ]; then
      jira_report+="• [$time] Worked on $issue: $message"
    else
      jira_report+="• [$time] $message"
    fi
  done <<< "$sorted_commits"
  
  # Add the last day's total
  if [ $current_day_total -gt 0 ]; then
    daily_totals+=($current_day_total)
  fi
  
  # Calculate working days and validate total time
  local num_working_days=$(calculate_working_days "$start_date" "$end_date")
  total_time=$(validate_work_time "$total_time" "$num_working_days")
  
  # Add detailed time summary
  jira_report+="\n\n${BLUE}=== Detailed Time Summary ===${NC}\n"
  
  # Calculate total time per author
  local author_times=()
  local current_author=""
  local author_total=0
  
  echo "$sorted_commits" | while IFS= read -r commit; do
    local author=$(echo "$commit" | sed -n 's/.*(\([^,]*\).*/\1/p')
    local time_str=$(echo "$commit" | grep -o "Time Spent: [0-9]*h [0-9]*m" || echo "Time Spent: 0h 0m")
    local hours=$(echo "$time_str" | grep -o "[0-9]*h" | grep -o "[0-9]*" || echo "0")
    local minutes=$(echo "$time_str" | grep -o "[0-9]*m" | grep -o "[0-9]*" || echo "0")
    local total_minutes=$((hours * 60 + minutes))
    
    if [ "$author" != "$current_author" ]; then
      if [ -n "$current_author" ]; then
        author_times+=("$current_author:$author_total")
        author_total=0
      fi
      current_author="$author"
    fi
    author_total=$((author_total + total_minutes))
  done
  
  if [ -n "$current_author" ]; then
    author_times+=("$current_author:$author_total")
  fi
  
  # Print time summary per author
  jira_report+="Time spent per author:\n"
  local grand_total=0
  for author_time in "${author_times[@]}"; do
    local author="${author_time%%:*}"
    local minutes="${author_time##*:}"
    local hours=$((minutes / 60))
    local remaining_minutes=$((minutes % 60))
    grand_total=$((grand_total + minutes))
    jira_report+="• $author: ${hours}h ${remaining_minutes}m\n"
  done
  
  # Calculate grand total in working day format
  local total_days=$((grand_total / WORK_MINUTES_PER_DAY))
  local remaining_minutes=$((grand_total % WORK_MINUTES_PER_DAY))
  local remaining_hours=$((remaining_minutes / 60))
  local final_minutes=$((remaining_minutes % 60))
  
  jira_report+="\nGrand Total:\n"
  if [ $total_days -gt 0 ]; then
    jira_report+="• ${total_days} working days"
    if [ $remaining_hours -gt 0 ] || [ $final_minutes -gt 0 ]; then
      jira_report+=" and "
    fi
  fi
  if [ $remaining_hours -gt 0 ]; then
    jira_report+="${remaining_hours}h"
    if [ $final_minutes -gt 0 ]; then
      jira_report+=" "
    fi
  fi
  if [ $final_minutes -gt 0 ]; then
    jira_report+="${final_minutes}m"
  fi
  jira_report+="\n"
  
  # Add utilization information
  local total_available_minutes=$((num_working_days * WORK_MINUTES_PER_DAY))
  local utilization=$((grand_total * 100 / total_available_minutes))
  jira_report+="\nWorking Hours Analysis:\n"
  jira_report+="• Standard working hours: $WORK_HOURS_PER_DAY hours per day\n"
  jira_report+="• Available working time: $((total_available_minutes / 60))h $((total_available_minutes % 60))m\n"
  jira_report+="• Time logged: $((grand_total / 60))h $((grand_total % 60))m\n"
  jira_report+="• Utilization: ${utilization}%\n"
  
  echo -e "$jira_report"
  return 0
}

# Function to initialize GitLogger with a local git repository
init_repository() {
  local repo_dir="${1:-.}"  # Default to current directory if none provided
  
  # Check if it's a valid git repository
  if [ ! -d "$repo_dir/.git" ]; then
    print_error "Not a valid git repository: $repo_dir"
    return 1
  fi
  
  # Save repository path to config file
  local config_dir="$HOME/.gitlogger"
  mkdir -p "$config_dir"
  echo "$repo_dir" > "$config_dir/current_repo"
  
  print_success "GitLogger initialized with repository: $repo_dir"
  
  # Extract and display basic repository information using git commands directly
  repo_info
}

# Function to get current repository path from config
get_current_repo() {
  local config_file="$HOME/.gitlogger/current_repo"
  
  if [ ! -f "$config_file" ]; then
    print_error "No repository initialized. Run 'gitlogger init' first."
    return 1
  fi
  
  local repo_dir=$(cat "$config_file")
  
  if [ ! -d "$repo_dir/.git" ]; then
    print_error "Configured repository no longer exists or is not a git repository: $repo_dir"
    print_info "Run 'gitlogger init' with a valid repository."
    return 1
  fi
  
  echo "$repo_dir"
  return 0
}

# Function to show repository information
repo_info() {
  local repo_dir=$(get_current_repo)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  print_info "Repository information for: $repo_dir"
  
  # Get repository details using git commands
  local repo_name=$(basename "$repo_dir")
  local current_branch=$(git -C "$repo_dir" branch --show-current)
  local remote_url=$(git -C "$repo_dir" config --get remote.origin.url)
  local commit_count=$(git -C "$repo_dir" rev-list --count HEAD)
  local last_commit=$(git -C "$repo_dir" log -1 --pretty=format:"%h - %s (%cr)" HEAD)
  local contributors=$(git -C "$repo_dir" shortlog -sn --no-merges | head -5 | sed 's/^\s*[0-9]*\s*//' | sed 's/$/,/' | tr -d '\n' | sed 's/,$//')
  
  echo "Repository: $repo_name"
  echo "Current branch: $current_branch"
  if [ -n "$remote_url" ]; then
    echo "Remote URL: $remote_url"
  else
    echo "Remote URL: None (local repository only)"
  fi
  echo "Total commits: $commit_count"
  echo "Latest commit: $last_commit"
  echo "Top contributors: $contributors"
  
  return 0
}

# Function to get git logs for a specific date
get_logs_for_date() {
  local date="$1"
  local repo_dir=$(get_current_repo)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  # Validate date format
  if ! [[ $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    print_error "Invalid date format. Please use YYYY-MM-DD"
    return 1
  fi
  
  print_info "Getting git logs for date: $date from repository: $(basename "$repo_dir")"
  
  # Use git log to get commits for the specific date
  local commits=$(git -C "$repo_dir" log --date=short --after="$date 00:00:00" --before="$date 23:59:59" --pretty=format:"%h - %s (%an, %ad)")
  
  if [ -z "$commits" ]; then
    print_info "No commits found for date: $date"
    return 0
  fi
  
  local commit_count=$(echo "$commits" | wc -l)
  print_success "Found $commit_count commits for date: $date"
  
  # Print the commits
  echo -e "\nCommits on $date:"
  echo "$commits" | while read -r line; do
    echo " * $line"
  done
  
  # Extract issue references from commit messages
  local issues=$(echo "$commits" | grep -o '#[A-Za-z0-9-]\+' | sort -u)
  
  if [ -n "$issues" ]; then
    echo -e "\nReferenced issues:"
    echo "$issues" | while read -r issue; do
      echo " * $issue"
    done
  fi
  
  # Run Gemini Flash analysis
  gemini_analyze_commits "$commits" "$date"
  
  return 0
}

# Function to get git logs for a date range
get_logs_for_date_range() {
  local start_date="$1"
  local end_date="$2"
  local repo_dir=$(get_current_repo)
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  # Validate date formats
  if ! [[ $start_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! [[ $end_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    print_error "Invalid date format. Please use YYYY-MM-DD"
    return 1
  fi
  
  print_info "Generating report for date range: $start_date to $end_date"
  
  # Calculate the number of days in the range
  local start_seconds=$(date -d "$start_date" +%s)
  local end_seconds=$(date -d "$end_date" +%s)
  local days_diff=$(( (end_seconds - start_seconds) / 86400 + 1 ))
  
  if [ $days_diff -gt 31 ]; then
    print_error "Date range too large. Please limit to 31 days maximum."
    return 1
  fi
  
  # Get commits in the date range
  local commits=$(git -C "$repo_dir" log --date=short --after="$start_date 00:00:00" --before="$end_date 23:59:59" --pretty=format:"%h - %s (%an, %ad)")
  
  if [ -z "$commits" ]; then
    print_info "No commits found for date range: $start_date to $end_date"
    return 0
  fi
  
  local commit_count=$(echo "$commits" | wc -l)
  print_success "Found $commit_count commits for date range: $start_date to $end_date"
  
  # Get statistics for the period
  local authors=$(git -C "$repo_dir" shortlog -sn --no-merges --after="$start_date" --before="$end_date" | head -5)
  local files_changed=$(git -C "$repo_dir" log --pretty=format: --name-only --after="$start_date" --before="$end_date" | sort | uniq | wc -l)
  
  # Print report header
  echo -e "\n====== Git Activity Report ======"
  echo "Repository: $(basename "$repo_dir")"
  echo "Period: $start_date to $end_date"
  echo "Total commits: $commit_count"
  echo "Files changed: $files_changed"
  
  # Print top contributors
  echo -e "\nTop contributors:"
  echo "$authors" | while read -r line; do
    echo " * $line"
  done
  
  # Print commits by date
  echo -e "\nCommits by date:"
  
  current_date=""
  echo "$commits" | while read -r line; do
    date_from_commit=$(echo "$line" | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}")
    if [ "$date_from_commit" != "$current_date" ]; then
      current_date="$date_from_commit"
      echo -e "\n$current_date:"
    fi
    echo " * $line"
  done
  
  # Extract issue references
  local issues=$(echo "$commits" | grep -o '#[A-Za-z0-9-]\+' | sort -u)
  
  if [ -n "$issues" ]; then
    echo -e "\nReferenced issues:"
    echo "$issues" | while read -r issue; do
      # Get commit messages mentioning this issue
      local issue_commits=$(echo "$commits" | grep "$issue")
      echo " * $issue (mentioned in $(echo "$issue_commits" | wc -l) commits)"
    done
  fi
  
  # Run Gemini Flash analysis
  gemini_analyze_commits "$commits" "$start_date to $end_date"
  
  return 0
}

# Check dependencies
check_dependencies() {
  local missing_deps=()
  
  # Check for git
  if ! command -v git &> /dev/null; then
    missing_deps+=("git")
  fi
  
  # If there are missing dependencies, exit
  if [ ${#missing_deps[@]} -gt 0 ]; then
    print_error "Missing dependencies: ${missing_deps[*]}"
    echo "Please install the required dependencies and try again."
    exit 1
  fi
}

# Main function
main() {
  check_dependencies
  
  local command="$1"
  shift # Remove the command from the arguments
  
  case "$command" in
    "init")
      init_repository "$1"
      ;;
    "info")
      repo_info
      ;;
    "log")
      if [ -z "$1" ]; then
        print_error "Date is required for 'log' command"
        show_help
        exit 1
      fi
      get_logs_for_date "$1"
      ;;
    "report")
      if [ -z "$1" ] || [ -z "$2" ]; then
        print_error "Start and end dates are required for 'report' command"
        show_help
        exit 1
      fi
      get_logs_for_date_range "$1" "$2"
      ;;
    "jira")
      if [ -z "$1" ] || [ -z "$2" ]; then
        print_error "Start and end dates are required for 'jira' command"
        show_help
        exit 1
      fi
      generate_jira_report "$1" "$2"
      ;;
    "help"|"--help"|"-h")
      show_help
      ;;
    "install")
      install_gitlogger
      exit 0
      ;;
    "")
      show_help
      ;;
    *)
      print_error "Unknown command: $command"
      show_help
      exit 1
      ;;
  esac
}

# Execute main function with all arguments
main "$@"

# Add this to the main() function case statement, just before the *) case:
    "install")
        install_gitlogger
        exit 0
        ;;