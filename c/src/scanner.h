#ifndef FRT_SCANNER_H
#define FRT_SCANNER_H

/*
 * Scan +in+ and copy the token into +out+, up until +out_size+ bytes.
 * The +start+ and +end+ are pointers to the original untouched token
 * somewhere inside +in+.  This token may not always be copied
 * verbatim into +out+.  For example, the http://google.com token will
 * be truncated down to just google.com during the copy.
 * +token_length+ is the size of the resulting token.
 */
void frt_std_scan(const char *in,
                  char *out, size_t out_size,
                  char **start, char **end,
                  int *token_length);

#endif /* FRT_SCANNER */
