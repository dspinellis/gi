#!/bin/sh
# shellcheck disable=SC2039,SC2164,SC2086,SC2103
#
# Shellcheck ignore list:
#  - SC2039: In POSIX sh, 'local' is undefined.
#    Rationale: Local makes for better code and works on many modern shells
#  - SC2164: Use cd ... || exit in case cd fails.
#    Rationale: We run this after creating the directory
#  - SC2164: Use a ( subshell ) to avoid having to cd back.
#    Rationale: We run this after creating the directory
#
#
# (C) Copyright 2016-2020 Diomidis Spinellis
#
# This file is part of gi, the Git-based issue management system.
#
# gi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# gi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with gi.  If not, see <http://www.gnu.org/licenses/>.
#

# Display a test's result
message()
{
  local okfail

  okfail=$1
  shift
  if [ "$1" ] ; then
    echo "$okfail $ntest - $*"
  else
    echo "$okfail $ntest - $testname"
  fi |
  sed "s/$gi_re/gi/"
}

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ok()
{
  message ${GREEN}ok${NC} "$*"
}

fail()
{
  printf "%d " "$ntest" >>"$TopDir/failure"
  message ${RED}fail${NC} "$*"
}

# Test specified command, which should succeed
try()
{
  local exit_code

  ntest=$((ntest + 1))
  echo "Test $ntest: $*" >>"$TopDir/error.log"
  "$@" >/dev/null 2>>"$TopDir/error.log"
  exit_code=$?
  cd .issues
  if git status | grep 'not staged' >/dev/null ; then
    fail staging "$*"
  else
    ok staging "$*"
  fi
  cd ..
  start
  if [ $exit_code = 0 ] ; then
    ok "$*"
  else
    fail "$*"
  fi
}

# Test specified command, which should fail
ntry()
{
  ntest=$((ntest + 1))
  if ! "$@" >/dev/null 2>&1 ; then
    ok "fail $*"
  else
    fail "fail $*"
  fi
}

# grep for the specified pattern, which should be found
# Does not increment ntest, because it is executed as a separate process
try_grep()
{
  test -z "$testname" && echo "Test $ntest: grep $*" >>"$TopDir/error.log"
  if tee input | grep "$@" >/dev/null 2>&1 ; then
    ok "grep $*"
  else
    fail "grep $*"
    echo 'Input:' >>"$TopDir/error.log"
    cat input >>"$TopDir/error.log"
  fi
}

# grep for the specified pattern, which should not be found
# Does not increment ntest, because it is executed as a separate process
try_ngrep()
{
  test -z "$testname" && echo "Test $ntest: ! grep $*" >>"$TopDir/error.log"
  if ! tee input | grep "$@" >/dev/null 2>&1 ; then
    ok "not grep $1"
  else
    fail "not grep $1"
    echo 'Input:' >>"$TopDir/error.log"
    cat input >>"$TopDir/error.log"
  fi
}

# Start a new test with the specified description
start()
{
  ntest=$((ntest + 1))
  testname="$*"
  test -n "$testname" && echo "Test $ntest: $*" >>"$TopDir/error.log"
}

# Fold header continuation lines
header_continuation()
{
sed -n '
# Header
/^[^ 	]/ {
  # Print previous hold space
  x
  s/\n//g
  /^./p
  x
  # Keep in hold space
  h
}
# Continuation
/^[ 	]/ {
  # Append to hold space
  H
}
$ {
  # Print previous hold space
  x
  s/\n/ /g
  /^./p
}
'
}

TopDir=$(mktemp -d)
{
  jq --version || exit 1
  curl --version
  echo "Test artifacts saved in $TopDir"
} 1>&2

if command -v gdate ; then
  DATEBIN="gdate"                
else
  DATEBIN="date"
fi

# Setup GitHub authentication token for Travis CI for curl version >= 7.55
# The GH_TOKEN environment variable with the secret token is specified in
# https://travis-ci.org/dspinellis/git-issue/settings
if [ -n "$GH_TOKEN" ] &&  curl --version | awk '/curl/{exit $2 >= "7.55" ? 0 : 1}' ; then
  echo "Authorization: token $GH_TOKEN" >"$HOME/.token"
  export GH_CURL_AUTH="Authorization: token $GH_TOKEN"
  echo "Set GH_CURL_AUTH to $GH_CURL_AUTH using GH_TOKEN"
fi

echo 'TAP version 13'
ntest=0
gi="$(cd "$(dirname "$0")" && pwd)"/git-issue.sh
gi_re=$(echo "$gi" | sed 's/[^0-9A-Za-z]/\\&/g')

start sync-docs
GenFiles='git-issue.sh git-issue.1'
if ! git diff --quiet HEAD ; then
  fail "Uncommitted files sync-docs test skipped and pending"
else
  sh sync-docs.sh --no-user-agent
  Status=$(git status --porcelain -- $GenFiles)
  if [ -z "$Status" ]; then
      ok "make sync-docs left $GenFiles as committed"
  else
      fail "make sync-docs changed $GenFiles"
      git diff -- $GenFiles >>"$TopDir/error.log"
      git checkout -- $GenFiles
  fi
fi
cd "$TopDir"

mkdir testdir
cd testdir

try "$gi" init
try "$gi" list

start ; "$gi" list "$issue" | try_ngrep .

# New
try "$gi" new -s 'First-issue'
start ; "$gi" list | try_grep 'First-issue'

# New with editor
export VISUAL='mv ../issue-desc '

# Empty summary/description should fail
touch issue-desc
ntry "$gi" new

cat <<EOF >issue-desc
Second issue

Line in description
EOF
try "$gi" new

issue=$("$gi" list | awk '/Second issue/{print $1}')
issue2=$("$gi" list | awk '/First-issue/{print $1}')

# Show
start ; "$gi" show "$issue" | try_grep 'Second issue'
start ; "$gi" show "$issue" | try_grep 'Line in description'
start ; "$gi" show "$issue" | try_grep '^Author:'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Tags:[ 	]*open'
ntry "$gi" show xyzzy

# Edit

# Unmodified issue should fail
ntry "$gi" edit "$issue"

cat <<EOF >issue-desc
Second issue

Modified line in description
EOF
try "$gi" edit "$issue"
start ; "$gi" show "$issue" | try_grep 'Second issue'
start ; "$gi" show "$issue" | try_grep 'Modified line in description'
start ; "$gi" show "$issue" | try_ngrep 'Line in description'

export VISUAL=

# Comment
start
cat <<EOF >comment
Comment line
another line
EOF
export VISUAL='mv ../comment '; try "$gi" comment "$issue"
export VISUAL=
start ; "$gi" show -c "$issue" | try_grep 'another line'

# Comment editing
start
cat <<EOF >comment
Comment first line
comment second line
EOF
commentsha=$("$gi" show -c "$issue" | awk '/comment/{print $2}')
export VISUAL='mv ../comment '; try "$gi" edit -c "$commentsha"
# Try passing issue sha as comment sha
export VISUAL='mv ../comment '; ntry "$gi" edit -c "$issue"
export VISUAL=
start ; "$gi" show -c "$issue" | try_grep 'comment second line'
start ; "$gi" show -c "$issue" | try_ngrep 'another comment line'

# Assign
try "$gi" assign "$issue" joe@example.com
ntry "$gi" assign "$issue" joe@example.com
start ; "$gi" show "$issue" | header_continuation | try_grep '^Assigned-to:[ 	]joe@example.com'
try "$gi" assign "$issue" jane@example.com
start ; "$gi" show "$issue" | header_continuation | try_grep '^Assigned-to:.*jane@example.com'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Assigned-to:.*joe@example.com'
try "$gi" assign -r "$issue" joe@example.com
start ; "$gi" show "$issue" | header_continuation | try_ngrep '^Assigned-to:.*joe@example.com'
ntry "$gi" assign -r "$issue" joe@example.com
try "$gi" assign -r "$issue" jane@example.com
start ; "$gi" show "$issue" | header_continuation | try_ngrep '^Assigned-to:.*jane@example.com'
try "$gi" assign "$issue" joe@example.com

# Milestone
ntry "$gi" list ver2
try "$gi" milestone "$issue" ver2
start ; "$gi" list ver2 | try_grep "$issue"
start ; "$gi" show "$issue" | try_grep '^Milestone:[ 	]ver2'
try "$gi" milestone "$issue" ver2
try "$gi" milestone "$issue" ver3
start ; "$gi" show "$issue" | try_grep '^Milestone:[ 	]ver3'
start ; "$gi" show "$issue" | try_ngrep ver2
ntry "$gi" milestone -r "$issue" foo
try "$gi" milestone -r "$issue"
start ; "$gi" show "$issue" | try_ngrep ver3

# Weight
ntry "$gi" weight "$issue" l33t
ntry "$gi" weight -r "$issue"
try "$gi" weight "$issue" 1337
start ; "$gi" show "$issue" | try_grep 1337
try "$gi" weight -r "$issue"
start ; "$gi" show "$issue" | try_ngrep 1337

# Due Date
ntry "$gi" duedate "$issue" someday
ntry "$gi" duedate -r "$issue"
ntry "$gi" duedate -r "$issue" someday
start ; "$gi" duedate "$issue" yesterday | try_grep Warning
try "$gi" duedate "$issue" tomorrow
start ; "$gi" show "$issue" | try_grep "$($DATEBIN --date=tomorrow --rfc-3339=date)"
try "$gi" duedate -r "$issue"
start ; "$gi" show "$issue" | try_ngrep 'Due Date'

# Time Spent/Time Estimate
ntry "$gi" timespent "$issue" alot
ntry "$gi" timespent -r "$issue"
ntry "$gi" timespent -r "$issue" alot
ntry "$gi" timeestimate "$issue" alot
ntry "$gi" timeestimate -r "$issue"
ntry "$gi" timeestimate -r "$issue" 3months
try "$gi" timespent "$issue" 2hours
start ; "$gi" show "$issue" | try_grep '^Time Spent: 02 hours '
try "$gi" timespent -a "$issue" 3hours
start ; "$gi" show "$issue" | try_grep '^Time Spent: 05 hours '
try "$gi" timeestimate "$issue" 3days
try "$gi" timespent -a "$issue" 15minutes
# start ; "$gi" show "$issue" | try_grep 'Time Spent/Time Estimated: 05 hours 15 minutes \?/ \?3 days'
try "$gi" timespent -r "$issue"
start ; "$gi" show "$issue" | try_grep 'Time Estimate: 3 days'

# Watchers
try "$gi" watcher "$issue" jane@example.com
start ; "$gi" show "$issue" | header_continuation | try_grep '^Watchers:[ 	]jane@example.com'
try "$gi" watcher "$issue" alice@example.com
ntry "$gi" watcher "$issue" alice@example.com
start ; "$gi" show "$issue" | header_continuation | try_grep '^Watchers:.*jane@example.com'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Watchers:.*alice@example.com'
try "$gi" watcher -r "$issue" alice@example.com
start ; "$gi" show "$issue" | header_continuation | try_ngrep '^Watchers:.*alice@example.com'
try "$gi" watcher "$issue" alice@example.com

# Tags (most also tested through watchers)
try "$gi" tag "$issue" feature
start ; "$gi" show "$issue" | header_continuation | try_grep '^Tags:.*feature'
ntry "$gi" tag "$issue" feature

# List by tag
start ; "$gi" list feature | try_grep 'Second issue'
start ; "$gi" list open | try_grep 'First-issue'
start ; "$gi" list feature | try_ngrep 'First-issue'
try "$gi" tag -r "$issue" feature
start ; "$gi" list feature 2>/dev/null | try_ngrep 'Second issue'
try "$gi" tag "$issue" feature


# Long list
start ; "$gi" list -l oneline feature | try_grep 'Second issue'
start ; "$gi" list -l oneline feature | try_ngrep 'First-issue'
start ; "$gi" list -l "Tags:%T" | try_grep 'feature'
try "$gi" milestone "$issue" ver2
try "$gi" weight "$issue" 99
start ; "$gi" list -l full | try_grep 'ver2'
start ; "$gi" list -l compact | try_grep 'Weight: 99'
try "$gi" milestone -r "$issue"

# Long list ordering

ntry "$gi" list -l short -o "%iA"
start ; "$gi" list -l oneline -o "%D" | head -n 1 | try_grep 'First-issue'
start ; "$gi" list -l oneline -o "%D" -r | head -n 1 | try_grep 'Second issue'
start ; "$gi" list -l short -o "%T" | head -n 4 | try_grep 'feature'

# Filter-apply

cat <<EOF >test-filter.sh
#!/bin/sh
echo "Line added by test-filter" >> description
EOF

chmod +x test-filter.sh
start ; "$gi" filter-apply test-filter.sh | try_grep "Filter applied"
start ; "$gi" show "$issue" | try_grep "Line added by test-filter"
# Reset changes
"$gi" git checkout -- .

# close
try "$gi" close "$issue"
start ; "$gi" list | try_ngrep 'Second issue'
start ; "$gi" list closed | try_grep 'Second issue'

# log
try "$gi" log
start ; n=$("$gi" log | tee foo | grep -c gi:)
try test "$n" -ge 18

# clone
# Required in order to allow a push to a non-bare repo
"$gi" git config --add receive.denyCurrentBranch ignore
cd ..
rm -rf testdir2
mkdir testdir2
cd testdir2
git clone ../testdir/.issues/ 2>/dev/null
start ; "$gi" show "$issue" | header_continuation | try_grep '^Watchers:.*alice@example.com'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Tags:.*feature'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Assigned-to:.*joe@example.com'
start ; "$gi" show "$issue" | try_grep 'Second issue'
start ; "$gi" show "$issue" | try_grep 'Modified line in description'
start ; "$gi" show "$issue" | try_grep '^Author:'
start ; "$gi" show "$issue" | header_continuation | try_grep '^Tags:.*closed'

# Push and pull
try "$gi" tag "$issue" cloned
try "$gi" push
cd ../testdir
"$gi" git reset --hard >/dev/null # Required, because we pushed to a non-bare repo
start ; "$gi" show "$issue" | header_continuation | try_grep '^Tags:.*cloned'

# Pull
try "$gi" tag "$issue" modified-upstream
cd ../testdir2
try "$gi" pull
"$gi" show "$issue" | try_grep modified-upstream
cd ../testdir

if [ -z "$GH_CURL_AUTH" ] ; then
  echo "Skipping GitHub import/export tests due to lack of GitHub authentication token."
else
  # Import
  # GitHub
  echo "Starting GitHub import tests..."
  try "$gi" import github dspinellis git-issue-test-issues
  start ; "$gi" list | try_grep 'An open issue on GitHub with a description and comments'
  # Closed issues
  start ; "$gi" list | try_grep -v 'A closed issue on GitHub without description'
  start ; "$gi" list -a | try_grep 'A closed issue on GitHub without description'
  # Description and comments
  issue=$("$gi" list | awk '/An open issue on GitHub with a description and comments/ {print $1}')
  start ; "$gi" show "$issue" | try_grep '^ *line 1$'
  start ; "$gi" show "$issue" | try_grep '^ *line 2$'
  start ; "$gi" show "$issue" | try_grep 'Line 3 with special characters "'\''<>|\$'
  start ; "$gi" show -c "$issue" | try_grep '^ *comment 1 line 1$'
  start ; "$gi" show -c "$issue" | try_grep '^ *comment 1 line 2$'
  start ; "$gi" show -c "$issue" | try_grep '^ *comment 2$'
  start ; "$gi" show -c "$issue" | try_grep '^ *comment 4$'
  start ; "$gi" show "$issue" | try_grep '^GitHub issue: #[0-9]* at dspinellis/git-issue-test-issues$'
  # Assignees and tags
  issue=$("$gi" list | awk '/An open issue on GitHub with assignees and tags/ {print $1}')
  start ; "$gi" show "$issue" | try_grep 'good first issue'
  start ; "$gi" show "$issue" | header_continuation | try_grep 'Assigned-to:.*dspinellis'
  start ; "$gi" show "$issue" | header_continuation | try_grep 'Assigned-to:.*louridas'
  # Milestone
  try "$gi" list ver3
  # Import should be idempotent
  before=$(cd .issues ; git rev-parse --short HEAD)
  try "$gi" import github dspinellis git-issue-test-issues
  after=$(cd .issues ; git rev-parse --short HEAD)
  try test x"$before" = x"$after"

  # Export
  # create new repository to test issue exporting
  echo "Trying to create GitHub repository..."
  curl -H "$GH_CURL_AUTH" -s --data '{"name": "git-issue-test-export-'"$($DATEBIN -Is | tr ':+' '--')"'", "private": true}' --output ghrepo https://api.github.com/user/repos
  if  grep "git-issue-test-export" > /dev/null < ghrepo ; then
    echo "Starting export tests..."
    ghrepo=$(jq --raw-output '.full_name' < ghrepo | tr '/' ' ')
    ghrepourl=$(jq --raw-output '.url' < ghrepo)
    ghuser=$(jq --raw-output '.owner.login' < ghrepo)
    # remove assignees to prevent notifications about test issues on GitHub
    "$gi" assign -r "$issue" dspinellis > /dev/null 2>&1
    "$gi" assign -r "$issue" louridas > /dev/null 2>&1
    try "$gi" create -n "$issue" github $ghrepo
    # Get the created issue
    try "$gi" create -u "$(jq -r '.number' .issues/create-body)" "$issue" github $ghrepo
    rm -f .issues/create-body .issues/create-header
    # modify and export
    try "$gi" create -n "$issue2" github $ghrepo
    try "$gi" new -c "github $ghrepo" -s "Issue exported directly"
    "$gi" assign "$issue2" "$ghuser" > /dev/null 2>&1
    try "$gi" export github $ghrepo
    start ; "$gi" export github $ghrepo | try_grep "Issue $issue.* not modified, skipping..."
    # Test invalid assignee
    "$gi" assign "$issue2" octocat > /dev/null 2>&1
    start ; "$gi" export github $ghrepo | try_grep "Couldn't add assignee octocat. Skipping..."
    "$gi" assign -r "$issue2" octocat > /dev/null 2>&1

    # test milestone creation
    "$gi" new -s "milestone issue" > /dev/null 2>&1
    issue3=$("$gi" list | awk '/milestone issue/{print $1}')
    "$gi" milestone "$issue3" ver4 > /dev/null 2>&1
    "$gi" duedate "$issue3" week > /dev/null 2>&1
    "$gi" timeestimate "$issue3" 3hours > /dev/null 2>&1
    try "$gi" create -e "$issue3" github $ghrepo
    try "$gi" exportall -a github $ghrepo

    # Basic round-trip tests
    echo "Starting GitHub round-trip test..."
    cd ..
    mkdir testdir3
    cd testdir3
    "$gi" init
    try "$gi" import github $ghrepo
    rissue=$("$gi" list | awk '/An open issue on GitHub with a description and comments/ {print $1}')
    rissue2=$("$gi" list | awk '/milestone issue/{print $1}')
    start ; "$gi" show "$rissue" | try_grep '^ *line 1'
    start ; "$gi" show "$rissue" | try_grep '^ *line 2'
    start ; "$gi" show "$rissue" | try_grep 'Line 3 with special characters "'\''<>|\$'
    start ; "$gi" show -c "$rissue" | try_grep '^ *comment 1 line 1'
    start ; "$gi" show -c "$rissue" | try_grep '^ *comment 1 line 2'
    start ; "$gi" show -c "$rissue" | try_grep '^ *comment 2'
    start ; "$gi" show -c "$rissue" | try_grep '^ *comment 4'
 
    start ; "$gi" show "$rissue2" | try_grep '^Milestone: ver4'
    rissue3=$("$gi" list | awk '/An open issue on GitHub with assignees and tags/ {print $1}')
    start ; "$gi" show "$rissue3" | try_grep 'good first issue'
    
    cd ../testdir

    # delete repo
    curl -H "$GH_CURL_AUTH" -s --request DELETE $ghrepourl |
      grep "{" && printf "Couldn't delete repository.
You probably don't have delete permittions activated on the OAUTH token.\\nPlease delete %s manually." "$ghrepo"

  else
    echo "Couldn't create test repository. Skipping export tests."
  fi
fi

# shellcheck disable=2153
if [ -z "$GL_CURL_AUTH" ] ; then
  echo "Skipping GitLab import/export tests due to lack of GitLab authentication token."
else
  # Import
  echo "Starting GitLab import tests..."
  try "$gi" import gitlab vyrondrosos git-issue-test-issues
  start ; "$gi" list | try_grep 'An open issue on GitLab with a description and comments'
  # Closed issues
  start ; "$gi" list | try_grep -v 'A closed issue on GitLab without description'
  start ; "$gi" list -a | try_grep 'A closed issue on GitLab without description'
  # Description and comments
  glissue=$("$gi" list | awk '/An open issue on GitLab with a description and comments/ {print $1}')
  start ; "$gi" show "$glissue" | try_grep '^ *line 1$'
  start ; "$gi" show "$glissue" | try_grep '^ *line 2$'
  start ; "$gi" show "$glissue" | try_grep 'Line 3 with special characters "'\''<>|\$'
  start ; "$gi" show -c "$glissue" | try_grep '^ *comment 2$'
  start ; "$gi" show -c "$glissue" | try_grep '^ *comment 3$'
  start ; "$gi" show -c "$glissue" | try_grep '^ *comment 4$'
  start ; "$gi" show "$glissue" | try_grep '^GitLab issue: #[0-9]* at vyrondrosos/git-issue-test-issues$'
  # Assignees and tags
  glissue=$("$gi" list | awk '/An open issue on GitLab with assignees and tags/ {print $1}')
  start ; "$gi" show "$glissue" | try_grep 'good first issue'
  start ; "$gi" show "$glissue" | header_continuation | try_grep 'Assigned-to:.*'"$gluser"
  # Milestone
  try "$gi" list ver3
  # Import should be idempotent
  before=$(cd .issues ; git rev-parse --short HEAD)
  try "$gi" import gitlab vyrondrosos git-issue-test-issues
  after=$(cd .issues ; git rev-parse --short HEAD)
  try test x"$before" = x"$after"

  # Import repo belonging to group
  try "$gi" import gitlab git-issue-test-group git-issue-subgroup-test/git-issue-group-test
  start ; "$gi" list | try_grep 'Issue in group repo'
  glissue2=$("$gi" list | awk '/Issue in group repo/ {print $1}')
  start ; "$gi" show "$glissue2" | try_grep '^GitLab issue: #1 at git-issue-test-group/git-issue-subgroup-test/git-issue-group-test$'

  # Export
  # Create new repository to test issue exporting
  echo "Trying to create GitLab repository..."
  curl -H "$GL_CURL_AUTH" -s --header "Content-Type: application/json" --data '{"name": "git-issue-test-export-'"$($DATEBIN -Is | tr ':+' '--')"'", "visibility": "private"}' --output glrepo https://gitlab.com/api/v4/projects
  if  grep "git-issue-test-export" > /dev/null < glrepo ; then
    echo "Starting export tests..."
    glrepo=$(jq --raw-output '.path_with_namespace' < glrepo | tr '/' ' ')
    glrepourl=$(jq --raw-output '._links.self' < glrepo)
    gluser=$(jq --raw-output '.owner.username' < glrepo)
    try "$gi" create -n "$issue" gitlab $glrepo
    # Get the created issue
    try "$gi" create -u "$(jq -r '.iid' .issues/create-body)" "$issue" gitlab $glrepo
    rm -f .issues/create-body .issues/create-header
    # modify and export
    try "$gi" create -n "$issue2" gitlab $glrepo
    try "$gi" new -c "gitlab $glrepo" -s "Issue exported directly"
    "$gi" assign "$issue2" "$gluser" > /dev/null 2>&1
    try "$gi" export gitlab $glrepo

    "$gi" assign "$issue2" octocat > /dev/null 2>&1
    try "$gi" export gitlab $glrepo
    "$gi" assign -r "$issue2" octocat > /dev/null 2>&1

    # test milestone creation
    "$gi" new -s "gitlab milestone issue : %M" > /dev/null 2>&1
    glissue3=$("$gi" list | awk '/gitlab milestone issue : %M/{print $1}')
    "$gi" milestone "$glissue3" ver4 > /dev/null 2>&1
    "$gi" duedate "$glissue3" week > /dev/null 2>&1
    "$gi" timeestimate "$glissue3" 3hours > /dev/null 2>&1
    try "$gi" create -e "$glissue3" gitlab $glrepo
    start ; "$gi" show "$glissue3" | try_grep 'ver4'
    # Try to create duplicate
    ntry "$gi" create -e "$glissue3" gitlab $glrepo
    try "$gi" exportall -a gitlab $glrepo

    # Basic GitLab round-trip tests
    echo "Starting GitHub round-trip test..."
    cd ..
    mkdir testdir4
    cd testdir4
    "$gi" init
    try "$gi" import gitlab $glrepo
    start ; "$gi" list | try_grep 'An open issue on GitLab with a description and comments'
    # Closed issues
    start ; "$gi" list | try_grep -v 'A closed issue on GitLab without description'
    start ; "$gi" list -a | try_grep 'A closed issue on GitLab without description'
    # Description and comments
    rglissue=$("$gi" list | awk '/An open issue on GitLab with a description and comments/ {print $1}')
    rglissue2=$("$gi" list | awk '/gitlab milestone issue/ {print $1}')
    start ; "$gi" show "$rglissue" | try_grep '^ *line 1'
    start ; "$gi" show "$rglissue" | try_grep '^ *line 2'
    start ; "$gi" show "$rglissue" | try_grep 'Line 3 with special characters "'\''<>|\$'
    start ; "$gi" show -c "$rglissue" | try_grep '^ *comment 2'
    start ; "$gi" show -c "$rglissue" | try_grep '^ *comment 3'
    start ; "$gi" show -c "$rglissue" | try_grep '^ *comment 4'
    start ; "$gi" show "$rglissue" | try_grep '^GitLab issue: #[0-9]* at vyrondrosos/git-issue'

    start ; "$gi" show "$rglissue2" | try_grep "^Due Date: $($DATEBIN --date=week --rfc-3339=date)"
    start ; "$gi" show "$rglissue2" | try_grep '^Time Estimate: 03 hours'
    start ; "$gi" show "$rglissue2" | try_grep '^Milestone: ver4'
    # Assignees and tags
    rglissue3=$("$gi" list | awk '/An open issue on GitLab with assignees and tags/ {print $1}')
    start ; "$gi" show "$rglissue3" | try_grep 'good first issue'
    start ; "$gi" show "$rglissue3" | header_continuation | try_grep 'Assigned-to:.*'"$gluser"

    cd ../testdir
    # delete repo
    curl -H "$GL_CURL_AUTH" -s --request DELETE $glrepourl |
      grep "Accepted" > /dev/null || printf "Couldn't delete repository.
You probably don't have delete permittions activated on the OAUTH token.\\nPlease delete %s manually." "$glrepo"
  else
    echo "Couldn't create test repository. Skipping export tests."
  fi

fi

if ! [ -r "$TopDir/failure" ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some test(s) failed: $(cat "$TopDir/failure")"
  if [ -n "$TRAVIS_OS_NAME" ] ; then
    echo 'Error output follows' 1>&2
    cat "$TopDir/error.log" 1>&2
  else
    echo "Error output is in $TopDir/error.log"
  fi
  exit 1
fi
