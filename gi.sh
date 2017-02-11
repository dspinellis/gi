#!/bin/sh
#
# (C) Copyright 2016 Diomidis Spinellis
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

# Display system usage and exit
usage()
{
  # The following list is automatically created from README.md
  cat <<\USAGE_EOF
usage: gi <command> [<args>]
The following commands are available
gi init: Create a new issues repository in the current directory.
gi clone: Clone the specified remote repository.
gi new: Create a new open issue with the specified summary.
gi list: List the issues with the specified tag.
gi show: Show specified issue.
gi comment: Add an issue comment.
gi tag: Add (or remove with -r) a tag.
gi assign: Assign (or reassign) an issue to a person.
gi attach: Attach (or remove with -r) a file to an issue.
gi watcher: Add (or remove with -r) an issue watcher.
gi close: Remove the open tag from the issue, marking it as closed.
gi edit: Edit the specified issue's summary or comment.
gi log: Output a log of changes made
gi push: Update remote repository with local changes.
gi pull: Update local repository with remote changes.
gi git: Run the specified Git command on the issues repository.
USAGE_EOF
  exit 2
}

# Exit after displaying the specified error
error()
{
  echo "$1" 1>&2
  exit 1
}

# Return a unique identifier for the specified file
filesysid()
{
  stat --printf='%d:%i' "$1" 2>/dev/null ||
    stat -f '%d:%i' "$1"
}

# Move to the .issues directory
cdissues()
{
  while : ; do
    cd .issues 2>/dev/null && return
    if [ $(filesysid .) = $(filesysid /) ] ; then
      error 'Not an issues repository (or any of the parent directories)'
    fi
    cd ..
  done
}

# Output the path of an issue given its SHA
# issue_path_full <SHA>
issue_path_full()
{
  local sha partial path

  sha="$1"
  echo issues/$(expr $sha : '\(..\)')/$(expr $sha : '..\(.*\)'$)
}

# Output the path of an issue given its (possibly partial) SHA
# Abort with an error if the full path can not be uniquely resolved
# to an existing issue
# issue_path_part <SHA>
issue_path_part()
{
  local sha partial path

  sha="$1"
  partial=$(issue_path_full "$sha")
  path=$(echo ${partial}*)
  test -d "$path" || error "Unknown or ambigious issue specification $sha"
  echo $path
}

# Given an issue path return its SHA
issue_sha()
{
    echo "$1" | sed 's/issues\/\(..\)\/\([^/]*\).*/\1\2/'
}

# Shorten a full SHA
short_sha()
{
  git rev-parse --short "$1"
}

# Start an issue transaction
trans_start()
{
  cdissues
  start_sha=$(git rev-parse HEAD)
}

# Abort an issue transaction and exit with an error
trans_abort()
{
  git reset $start_sha
  git clean -qfd
  git checkout -- .
  echo 'Operation aborted' 1>&2
  exit 1
}

# Commit an issue's changes
# commit <summary> <message>
commit()
{
  git commit --allow-empty -q -m "$1

$2" || trans_abort
}

# Allow the user to edit the specified file
# Remove lines starting with '#'
# Succeed if the resulting file is non-empty
edit()
{
  local file
  editor=$(git config --get core.editor) || ${VISUAL:-vi}
  
  file="$1"
  ${editor} "$file" || return 1
  grep -v '^#' "$file" >"$file.new"
  if [ $(grep -c . "$file.new") -eq 0 ] ; then
    echo 'Empty file' 1>&2
    rm -f "$file.new"
    return 1
  fi
  mv "$file.new" "$file"
}

# Pipe input through the user's pager
pager()
{
  ${PAGER:-more}
}

# init: Initialize a new issue repository {{{1
sub_init()
{
  test -d .issues && error 'An .issues directory is already present'
  mkdir .issues || error 'Unable to create .issues directory'
  cdissues
  git init -q || error 'Unable to initialize Git directory'

  # Editing templates
  touch config || error 'Unable to create configuration file'
  mkdir templates || error 'Unable to create the templates directory'
  cat >templates/description <<\EOF

# Start with a one-line summary of the issue.  Leave a blank line and
# continue with the issue's detailed description.
#
# Remember:
# - Be precise
# - Be clear: explain how to reproduce the problem, step by step,
#   so others can reproduce the issue
# - Include only one problem per issue report
#
# Lines starting with '#' will be ignored, and an empty message aborts
# the issue addition.
EOF

  cat >templates/comment <<\EOF

# Please write here a comment regarding the issue.
# Keep the conversation constructive and polite.
# Lines starting with '#' will be ignored, and an empty message aborts
# the issue addition.
EOF
  cat >README.md <<\EOF
This is an distributed issue tracking repository based on Git.
Visit [gi](https://github.com/dspinellis/gi) for more information.
EOF
  git add config README.md templates/comment templates/description
  commit 'gi: Initialize issues repository' 'gi init'
  echo "Initialized empty issues repository in $(pwd)"
}

# new: Open a new issue {{{1
usage_new()
{
  cat <<\USAGE_new_EOF
gi new usage: gi new [-s summary]
USAGE_new_EOF
  exit 2
}

sub_new()
{
  local summary sha path

  while getopts s: flag ; do
    case $flag in
    s)
      summary="$OPTARG"
      ;;
    ?)
      usage_new
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  trans_start
  commit 'gi: Add issue' 'gi new mark'
  sha=$(git rev-parse HEAD)
  path=$(issue_path_full $sha)
  mkdir -p $path || trans_abort
  echo open >$path/tags || trans_abort
  if [ "$summary" ] ; then
    echo "$summary" >$path/description || trans_abort
  else
    cp templates/description $path/description || trans_abort
    edit $path/description || trans_abort
  fi
  git add $path/description $path/tags || trans_abort
  commit 'gi: Add issue description' "gi new description $sha"
  echo "Added issue $(short_sha $sha)"
}

# show: Show the specified issue {{{1
usage_show()
{
  cat <<\USAGE_show_EOF
gi show usage: gi show [-c] <sha>
-c	Show comments
USAGE_show_EOF
  exit 2
}

sub_show()
{
  local isha path comments

  while getopts c flag ; do
    case $flag in
    c)
      comments=1
      ;;
    ?)
      usage_show
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  test "$1" || usage_show

  cdissues
  path=$(issue_path_part $1) || exit
  isha=$(issue_sha $path)
  {
    # SHA, author, date
    echo "issue $isha"
    git show --no-patch --format='Author:	%an <%ae>
Date:	%aD' $isha

    # Tags
    if [ -s $path/tags ] ; then
      printf '%s' 'Tags:'
      fmt $path/tags | sed 's/^/	/'
    fi

    # Watchers
    if [ -s $path/watchers ] ; then
      printf '%s' 'Watchers:'
      fmt $path/watchers | sed 's/^/	/'
    fi

    # Assignee
    if [ -r $path/assignee ] ; then
      printf '%s' 'Assigned-to: '
      cat $path/assignee
    fi

    # Description
    echo
    sed 's/^/    /' $path/description

    # Comments
    test "$comments" || return
    git log --reverse --grep="^gi comment mark $isha" --format='%H' |
    while read csha ; do
      echo
      echo "comment $csha"
      git show --no-patch --format='Author:	%an <%ae>
Date:	%aD
' $csha
      sed 's/^/    /' $path/comments/$csha
    done
  } | pager
}

# clone: Clone the specified remote repository {{{1
usage_clone()
{
  cat <<\USAGE_clone_EOF
gi clone usage: gi clone <URL> <local-dir>
USAGE_clone_EOF
  exit 2
}

sub_clone()
{
  test "$1" -a "$2" || usage_clone
  mkdir -p "$2" || error "Unable to create local directory"
  cd "$2"
  git clone "$1" .issues
  echo "Cloned $1 into $2"
}

# assign: assign (or reassign) an issue to a person {{{1
usage_assign()
{
  cat <<\USAGE_tag_EOF
gi assign usage: gi assign <sha> email
USAGE_tag_EOF
  exit 2
}

sub_assign()
{
  local isha tag remove path

  test "$1" -a "$2" || usage_assign

  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha $path)
  printf "%s\n" "$2" >$path/assignee || error 'Unable to modify assignee file'
  trans_start
  git add $path/assignee || trans_abort
  commit 'gi: Assign issue' "gi assign $2"
  echo "Assigned to $2"
}

# Generic file add/remove entry {{{1
# file_add_rm [-r] entry-name filename sha entry ...
file_add_rm()
{
  local usage name file isha tag remove path

  name=$1
  shift
  file=$1
  shift
  usage=usage_$name

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      $usage
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  test "$1" -a "$2" || $usage

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha $path)
  touch $path/$file || error "Unable to modify $file file"
  for entry in "$@" ; do
    if [ "$remove" ] ; then
      grep -v "^$entry$" $path/$file >$path/$file.new
      if cmp $path/$file $path/$file.new >/dev/null 2>&1 ; then
	echo "No such $name entry: $entry" 1>&2
	rm $path/$file.new
	exit 1
      fi
      mv $path/$file.new $path/$file
      trans_start
      git add $path/$file || trans_abort
      commit "gi: Remove $name" "gi $name remove $entry"
      echo "Removed $name $entry"
    else
      if grep "^$entry$" $path/$file >/dev/null ; then
	echo "Entry $entry already exists" 1>&2
	exit 1
      fi
      printf "%s\n" "$entry" >>$path/$file
      trans_start
      git add $path/$file || trans_abort
      commit "gi: Add $name" "gi $name add $entry"
      echo "Added $name $entry"
    fi
  done
}

# tag: Add or remove an issue tag {{{1
usage_tag()
{
  cat <<\USAGE_tag_EOF
gi tag usage: gi tag [-r] <sha> <tag> ...
-r	Remove the specified tag
USAGE_tag_EOF
  exit 2
}

sub_tag()
{
  file_add_rm tag tags "$@"
}

# watcher: Add or remove an issue watcher {{{1
usage_watcher()
{
  cat <<\USAGE_watcher_EOF
gi watcher usage: gi watcher [-r] <sha> <tag> ...
-r	Remove the specified watcher
USAGE_watcher_EOF
  exit 2
}

sub_watcher()
{
  file_add_rm watcher watchers "$@"
}

# comment: Comment on an issue {{{1
usage_comment()
{
  cat <<\USAGE_comment_EOF
gi comment usage: gi comment <sha>
USAGE_comment_EOF
  exit 2
}

sub_comment()
{
  local isha csha path

  test "$1" || usage_comment

  cdissues
  path=$(issue_path_part $1) || exit
  isha=$(issue_sha $path)
  mkdir -p $path/comments || error "Unable to create comments directory"
  trans_start
  commit 'gi: Add comment' "gi comment mark $isha"
  csha=$(git rev-parse HEAD)
  cp templates/comment $path/comments/$csha || trans_abort
  edit $path/comments/$csha || trans_abort
  git add $path/comments/$csha || trans_abort
  commit 'gi: Add comment message' "gi comment message $isha $csha"
  echo "Added comment $(short_sha $csha)"
}

# list: Show issues matching a tag {{{1
usage_list()
{
  cat <<\USAGE_list_EOF
gi new usage: gi list [-a] [tag]
USAGE_list_EOF
  exit 2
}

sub_list()
{
  local all tag path id

  while getopts a flag ; do
    case $flag in
    a)
      all=1
      ;;
    ?)
      usage_list
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  tag="$1"
  : ${tag:=open}
  cdissues
  test -d issues || exit 0
  find issues -type f -name tags |
  if [ "$all" ] ; then
    cat
  else
    xargs grep -l "^$tag$"
  fi |
  while read tagpath ; do
    path=$(expr $tagpath : '\(.*\)/tags')
    id=$(echo $tagpath | sed 's/issues\/\(..\)\/\(.....\).*/\1\2/')
    printf '%s' "$id "
    head -1 $path/description
  done |
  sort -k 2 |
  pager
}

# log: Show log of issue changes {{{1
usage_log()
{
  cat <<\USAGE_log_EOF
gi new usage: gi log [-I issue-SHA] [git log options]
USAGE_log_EOF
  exit 2
}

sub_log()
{
  local grep_arg

  while getopts I: flag ; do
    case $flag in
    I)
      sha="$OPTARG"
      ;;
    ?)
      usage_log
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  cdissues
  if [ "$sha" ] ; then
    git log --grep="^gi new $sha" "$@"
  else
    git log "$@"
  fi

}

# Subcommand selection {{{1
test "$1" || usage
subcommand="$1"
shift
case "$subcommand" in
  init) # Initialize a new issue repository
    sub_init
    ;;
  clone) # Clone specified remote directory
    sub_clone "$@"
    ;;
  new) # Create a new issue and mark it as open.
    sub_new "$@"
    ;;
  list) # List the issues with the specified tag.
    sub_list "$@"
    ;;
  show) # Show specified issue.
    sub_show "$@"
    ;;
  comment) # Add an issue comment.
    sub_comment "$@"
    ;;
  tag) # Add (or remove with -r) a tag.
    sub_tag "$@"
    ;;
  assign) # Assign (or reassign) an issue to a person.
    sub_assign "$@"
    ;;
  attach) # Attach (or remove with -r) a file to an issue.
    echo 'Not implemented yet' 1>&2
    exit 1
    ;;
  watcher) # Add (or remove with -r) an issue watcher.
    sub_watcher "$@"
    ;;
  edit) # Edit the specified issue's summary or comment.
    echo 'Not implemented yet' 1>&2
    exit 1
    ;;
  close) # Remove the open tag from the issue, marking it as closed.
    sha="$1"
    sub_tag "$sha" closed
    sub_tag -r "$sha" open
    ;;
  log) # Output log of changes made
    sub_log "$@"
    ;;
  push) # Update remote repository with local changes.
    cdissues
    git push "$@"
    ;;
  pull) # Update local repository with remote changes.
    cdissues
    git pull "$@"
    ;;
  git) # Run the specified Git command on the issues repository.
    cdissues
    git "$@"
    ;;
  *)
    usage
      ;;
esac
