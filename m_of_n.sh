#!/bin/sh

# Roughly, for each key, for each other key, until you get to (m-1) you encrypt the payload to the rest of the keys.
# Then you encypt that to the higher key, and bundle all of those together with tar, and encrypt that to the higher, etc.
# At the top level you end up with a bunch of files, one for each user, that they can decrypt to get a tarball.
# That tarball contains a similar encrypted file for each other key.
# When given to that person, they can decrypt it to get another tarball to give to any of the others (not including the first)
# The second last person gets a single file that can be decrypted by any of the people who weren't in the path leading to that file.

KEYS=""
INPUTS=""
NUM=""

usage() {
	(
	printf "Encrypts given payloads to given keys, such that any N of them could decrypt the payload, but not less.\n"
	printf "  -n NUM   Number of keys required to decrypt the payloads\n"
	printf "  -r ID    Key ID of one of the recipients. Can be anything gpg understands\n"
	printf "  -f FILE  File to encrypt. If FILE is -, read from stdin\n"
	printf "           If multiple files are given, each of them are encrypted as separate blobs\n"
	printf "  If no files are given, stdin is assumed.\n"
	printf "  Other options must be specified. There must be more than NUM IDs given\n"
	) >&2
}

while getopts "hn:r:f:" flag; do
	case "$flag" in
		n) NUM="$OPTARG";;
		h)
			usage
			exit 0;;
		r)
			if echo "meow" | gpg --encrypt -r "$OPTARG" 2> /dev/null > /dev/null; then
				KEYS="$(printf '%s\n%s\n' "$KEYS" "$OPTARG")"
			else
				echo "\"$OPTARG\" is not a valid keyid" >&2
				exit 1
			fi;;
		f) 
			if [ -r "$OPTARG" -o "$OPTARG" = "-" ]; then
				FILES="$(printf '%s\n%s\n' "$FILES" "$OPTARG")"
			else
				echo "\"$OPTARG\" is not a valid file" >&2
				exit 1
			fi;;
	esac
done

# Remove first item, which will always be a blank line, and dedupe
KEYS="$(printf "%s" "$KEYS" | sed 1d | sort | uniq)"
FILES="$(printf "%s" "$FILES" | sed 1d | sort | uniq)"

if [ ! "$NUM" -gt 0 ]; then
	echo "Must be given an integer greater than 0" >&2
	exit 1
fi

if [ -z "$FILES" ]; then
	echo "No file given, assuming stdin" >&2
	FILES="-"
fi

if [ -z "$KEYS" -o "$(printf "%s\n" "$KEYS" | wc -l)" -le "$NUM" ]; then
	echo "Must be given more than "$NUM" keys." >&2
	exit 1
fi

echo "==NUM"
echo "$NUM"
echo "==KEYS"
echo "$KEYS"
echo "==FILES"
echo "$FILES"
