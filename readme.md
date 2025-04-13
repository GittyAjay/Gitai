# GitLogger

A JavaScript wrapper for GitLogger CLI - Git activity tracking and reporting tool. This package provides a simple interface to track git activity, generate reports, and create Jira work logs.

## Installation

```bash
npm install gitlogger
```

## Usage

### As a Library

```typescript
import { GitLogger } from 'gitlogger';

// Initialize with a repository path
const logger = new GitLogger('./my-repo', {
  workHoursPerDay: 8,
  workingStartTime: '09:00',
  workingEndTime: '17:00',
});

// Get repository information
const repoInfo = await logger.getRepoInfo();
console.log(repoInfo);

// Get logs for a specific date
const dailyLogs = await logger.getLogsForDate('2024-03-10');
console.log(dailyLogs);

// Get logs for a date range
const rangeLogs = await logger.getLogsForDateRange('2024-03-01', '2024-03-10');
console.log(rangeLogs);

// Generate Jira work log report
const jiraReport = await logger.generateJiraReport('2024-03-01', '2024-03-10');
console.log(jiraReport);
```

### As a CLI Tool

```bash
# Initialize GitLogger with a repository
gitlogger init ./my-repo

# Show repository information
gitlogger info

# Get logs for a specific date
gitlogger log 2024-03-10

# Get logs for a date range
gitlogger report 2024-03-01 2024-03-10

# Generate Jira work log report
gitlogger jira 2024-03-01 2024-03-10
```

## Features

- Track git activity and commits
- Generate detailed reports
- Create Jira work logs
- Support for date ranges
- Issue tracking
- Contributor statistics

## Configuration

The GitLogger class accepts the following configuration options:

```typescript
interface GitLoggerConfig {
  apiBase?: string; // API base URL (default: 'http://localhost:3000/api')
  workHoursPerDay?: number; // Working hours per day (default: 8)
  workingStartTime?: string; // Working day start time (default: '09:00')
  workingEndTime?: string; // Working day end time (default: '17:00')
  geminiApiKey?: string; // Gemini API key for AI-powered analysis
}
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
