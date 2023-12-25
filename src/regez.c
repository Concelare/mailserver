#include "regez.h"
#include <regex.h>

bool isIP(char ip[]) {
  regex_t regex;
  regcomp(&regex, "([0-9])\.([0-9])\.([0-9])\.([0-9])", REG_EXTENDED);
  
  int matches = regexec(&regex, ip, 0, 0, 0);

  regfree(&regex);

  if (matches != REG_NOMATCH) {
    return true;
  }  

  return false;
}

