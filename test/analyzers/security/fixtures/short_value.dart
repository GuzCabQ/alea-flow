// Expected: 0 issues — refreshToken value is only 16 chars but
// config sets min_secret_value_length: 64, so it does not flag.

const refreshToken = 'aaaaaaaaaaaaaaaa';
