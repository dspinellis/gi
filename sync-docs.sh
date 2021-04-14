#!/bin/sh
# shellcheck disable=SC1004,SC2039
#
# Shellcheck ignore list:
#  - SC1004: This backslash+linefeed is literal. Break outside single quotes
#    if you just want to break the line.
#    Rationale: Required to continue sed(1) lines
#  - SC2039: In POSIX sh, 'local' is undefined.
#    Rationale: Local makes for better code and works on many modern shells
#
# (C) Copyright 2016-2019 Diomidis Spinellis
#
# This file is part of git-issue, the Git-based issue management system.
#
# git-issue is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# git-issue is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with git-issue.  If not, see <http://www.gnu.org/licenses/>.
#

# Synchronize script and its documentation with the contents of the README file

SCRIPT_NAME=git-issue.sh
MAN_PAGE=git-issue.1

sed -n \
    -E '1,/^SYSCONFDIR/p; /^install:/,/^\S/ { /^\S/d; p; }' Makefile | \
  sed -E '{
    # remove Makefile leading no-echo @
    s/^\s*@?// ;
    # convert Makefile ?= conditional assignment to bash :-
    s/^([^? ]+)\s*\?=\s*(.*)$/\1=${\1:-\2}/g ;
    # convert $(VAR) to ${VAR}
    s/\$\(([^)]+)\)/${\1}/g
  }' > install_gfw.sh
chmod +x install_gfw.sh

# Update usage information in the script based on README.md
{
  sed -n '1,/^The following commands are available:/p' $SCRIPT_NAME
  # Keep lines from `### start ` to `git issue git`
  # shellcheck disable=SC2016
  sed -E -n '/^### Start/,/^\* `git issue git`/ {
    # Only keep listed commands or subheaders
    /^\* |^### /!d
    # Format headers by eliminating all preceding space
    s/^### (.*)/\
\1/g
    # Remove repetitive git issue
    s/git issue //g
    # Remove code markup
    s/`//g
    # Format commands, depending on length
    s/^\* ([^:]{3}): /   \1        /g
    s/^\* ([^:]{4}): /   \1       /g
    s/^\* ([^:]{5}): /   \1      /g
    s/^\* ([^:]{6}): /   \1     /g
    s/^\* ([^:]{7}): /   \1    /g
    s/^\* ([^:]{8}): /   \1   /g
    s/^\* ([^:]{9}): /   \1  /g

    p
  }' README.md | tee foo
  sed -n '/^USAGE_EOF/,$p' $SCRIPT_NAME
} |
if [ "$1" = "--no-user-agent" ] ; then
  cat
else
  # Update user agent version
  sed '/^USER_AGENT/s/\/tree.*/\/tree\/'"$(git rev-parse --short HEAD)/"
fi >newgi.sh
mv newgi.sh $SCRIPT_NAME
chmod +x git-issue.sh

# Update the specified man section from the specified README section
# pre-processing its body with the given sed command
replace_section()
{
  local man_section="$1"
  local md_section="$2"
  local command="$3"
  local extra_command="$4"

  {
    # Output until the specified section
    sed -n "1,/^\\.SH $man_section/p" $MAN_PAGE

    # Output specified section from README
    echo '.\" Auto-generated content from README.md; do not edit this section'
    # shellcheck disable=SC2016
    sed -n "/^## $md_section/,/^## / {
      $command"'
      # Remove section titles
      /^## /d
      /^###/d
      # Set code text with Courier (twice per line)
      s/`/\\fC/;s/`/\\fP/
      s/`/\\fC/;s/`/\\fP/
      # Set italic text (twice per line; not when switched to Courier)
      /\\fC/!s/_/\\fI/;/\\fC/!s/_/\\fP/
      /\\fC/!s/_/\\fI/;/\\fC/!s/_/\\fP/
      # Set first-level and second-level bullets
      s/^\* /.IP "" 4\
/
      s/^  \* /.IP "" 8\
/
      s/^    \* /.IP "" 12\
/
      # format urls
      s/\[\([^]]*\)\](\([^)]*\))/\1 <\2>/

      '"$extra_command"'
      p
    }' README.md

    # Output the rest of the man page
    sed -n "1,/^\\.SH $man_section/d;{/^\\.SH /,/xyzzy/p;}" $MAN_PAGE
  } >man-$$.1
  mv man-$$.1 $MAN_PAGE
}

# Update subcommands, implementation, and examples in the manual page
# from the README file
# shellcheck disable=SC2016
replace_section 'GIT ISSUE COMMANDS' 'Use' 's/^\* `\([^`]*\)`: /.RE\
.PP\
\\fB\1\\fP\
.RS 4\
/' 's/^  *//'

replace_section FILES 'Internals' '' 's/^  *//'
# shellcheck disable=SC2016
replace_section EXAMPLES 'Example session' '/```/d;/^###/N;s/^### \(.*\)/.fi\
.ft R\
.PP\
\1.ft C\
.nf/'
