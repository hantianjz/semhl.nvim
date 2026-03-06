// semhl.nvim troubleshooting scenarios (TypeScript)
//
// Suggested actions:
// 1) Toggle comments on lines containing identifiers.
// 2) Move class methods and verify highlight consistency.
// 3) Replace an identifier with a new name and check stale highlight cleanup.

type UserRecord = {
  userId: string;
  teamName: string;
};

const activeUser: UserRecord = {
  userId: "u-001",
  teamName: "core",
};

function formatUser(record: UserRecord): string {
  return `${record.userId}:${record.teamName}`;
}

function printUser(record: UserRecord): void {
  const formattedUser = formatUser(record);
  console.log(formattedUser);
}

printUser(activeUser);

// Scenario A: comment/uncomment this assignment.
// activeUser.teamName = "platform";

// Scenario B: rename `formattedUser` to `userLabel`.
// Scenario C: move `formatUser` below `printUser`.
