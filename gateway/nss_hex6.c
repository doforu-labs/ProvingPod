/*
 * libnss_hex6 - NSS module: returns a virtual user entry for any 6-char lowercase hex username
 *
 * Purpose: lets sshd's getpwnam() pre-check pass (avoiding the forced rejection via
 *          fake_password + valid=0), so the PAM layer pam_exec + expose_authtok can
 *          obtain the real password and complete dynamic creation.
 *
 * Design:
 *   uid  = 0x40000000 + hex value   (1073741824 ~ 1090519039, outside the real-user range)
 *   gid  = ephemeral group gid (resolved dynamically, fallback 1003), so sudoers %ephemeral passwordless jump works
 *   passwd password field returns 'x', shadow returns '*' (no expiry); pam_unix fallback always fails (short-circuited by pam_exec)
 *   getpwent/getspent return NOTFOUND, preventing enumeration spam over 16M entries
 *
 * Build: gcc -fPIC -shared -Wl,-soname,libnss_hex6.so.2 -o libnss_hex6.so.2 nss_hex6.c
 * Install: /usr/lib/x86_64-linux-gnu/libnss_hex6.so.2
 * nsswitch.conf: passwd: files hex6 systemd sss   /   shadow: files hex6 systemd sss
 */
#define _GNU_SOURCE
#include <nss.h>
#include <pwd.h>
#include <shadow.h>
#include <grp.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

#define HEX6_BASE   0x40000000u
#define HEX6_MASK   0x00FFFFFFu          /* max 6-digit hex value */
#define HEX6_GID_FB 1000                 /* ephemeral group gid fallback */

/* ---------- utility functions ---------- */

static int is_hex6(const char *name)
{
    size_t i;
    if (!name || strlen(name) != 6) return 0;
    for (i = 0; i < 6; i++) {
        unsigned char c = (unsigned char)name[i];
        if (!(isdigit(c) || (c >= 'a' && c <= 'f'))) return 0; /* lowercase hex only */
    }
    return 1;
}

static unsigned int hex6_uid(const char *name)
{
    unsigned int v = 0;
    int i;
    for (i = 0; i < 6; i++) {
        char c = name[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v += (unsigned int)(c - '0');
        else v += (unsigned int)(c - 'a' + 10);
    }
    return HEX6_BASE + v;
}

static int uid_to_hex6(unsigned int uid, char *out /* >=7 bytes */)
{
    unsigned int v;
    const char *hex = "0123456789abcdef";
    int i;
    if (uid < HEX6_BASE || uid > HEX6_BASE + HEX6_MASK) return -1;
    v = uid - HEX6_BASE;
    for (i = 5; i >= 0; i--) { out[i] = hex[v & 0xF]; v >>= 4; }
    out[6] = '\0';
    return 0;
}

static gid_t ephemeral_gid(void)
{
    struct group *gr = getgrnam("ephemeral");
    return gr ? gr->gr_gid : (gid_t)HEX6_GID_FB;
}

/* ---------- passwd ---------- */

enum nss_status _nss_hex6_getpwnam_r(const char *name, struct passwd *pwd,
                                     char *buffer, size_t buflen, int *errnop)
{
    gid_t gid;
    unsigned int uid;
    size_t need, nlen;
    char *start = buffer;

    if (!is_hex6(name)) { *errnop = ENOENT; return NSS_STATUS_NOTFOUND; }

    uid = hex6_uid(name);
    nlen = strlen(name);

    /* fields: name / passwd(x) / uid / gid / gecos("") / dir / shell */
    need = nlen + 1 + 2 + 1 + 1 + (nlen + 7) + 10 + 8;
    if (need > buflen) { *errnop = ERANGE; return NSS_STATUS_TRYAGAIN; }

    gid = ephemeral_gid();
    pwd->pw_uid = uid;
    pwd->pw_gid = gid;

    pwd->pw_name = buffer;
    memcpy(buffer, name, nlen); buffer[nlen] = '\0';
    buffer += nlen + 1;

    pwd->pw_passwd = buffer; strcpy(buffer, "x"); buffer += 2;

    pwd->pw_gecos = buffer; buffer[0] = '\0'; buffer += 1;

    pwd->pw_dir = buffer;
    snprintf(buffer, buflen - (size_t)(buffer - start), "/");
    buffer += strlen(buffer) + 1;

    pwd->pw_shell = buffer; strcpy(buffer, "/bin/bash"); buffer += 10;

    return NSS_STATUS_SUCCESS;
}

enum nss_status _nss_hex6_getpwuid_r(uid_t uid, struct passwd *pwd,
                                     char *buffer, size_t buflen, int *errnop)
{
    char name[7];
    if (uid_to_hex6((unsigned int)uid, name) != 0) {
        *errnop = ENOENT;
        return NSS_STATUS_NOTFOUND;
    }
    return _nss_hex6_getpwnam_r(name, pwd, buffer, buflen, errnop);
}

enum nss_status _nss_hex6_setpwent(void) { return NSS_STATUS_SUCCESS; }
enum nss_status _nss_hex6_endpwent(void) { return NSS_STATUS_SUCCESS; }

enum nss_status _nss_hex6_getpwent_r(struct passwd *pwd, char *buffer,
                                     size_t buflen, int *errnop)
{
    /* enumeration disabled: return no entries */
    (void)pwd; (void)buffer; (void)buflen;
    *errnop = ENOENT;
    return NSS_STATUS_NOTFOUND;
}

/* ---------- shadow ---------- */

enum nss_status _nss_hex6_getspnam_r(const char *name, struct spwd *sp,
                                     char *buffer, size_t buflen, int *errnop)
{
    size_t need, nlen;

    if (!is_hex6(name)) { *errnop = ENOENT; return NSS_STATUS_NOTFOUND; }

    nlen = strlen(name);
    need = nlen + 1      /* name */
         + 1 + 1         /* sp_pwdp '*' */
         + 4 * 32        /* numeric field headroom */
         + 16;
    if (need > buflen) { *errnop = ERANGE; return NSS_STATUS_TRYAGAIN; }

    sp->sp_namp = buffer;
    memcpy(buffer, name, nlen); buffer[nlen] = '\0';
    buffer += nlen + 1;

    sp->sp_pwdp = buffer; strcpy(buffer, "*"); buffer += 2;

    /* no expiry policy, so pam_unix in common-account never rejects due to account expiry */
    sp->sp_lstchg = 19000;
    sp->sp_min = 0;
    sp->sp_max = 99999;
    sp->sp_warn = 7;
    sp->sp_inact = -1;
    sp->sp_expire = -1;
    sp->sp_flag = 0;

    return NSS_STATUS_SUCCESS;
}

enum nss_status _nss_hex6_setspent(void) { return NSS_STATUS_SUCCESS; }
enum nss_status _nss_hex6_endspent(void) { return NSS_STATUS_SUCCESS; }

enum nss_status _nss_hex6_getspent_r(struct spwd *sp, char *buffer,
                                     size_t buflen, int *errnop)
{
    (void)sp; (void)buffer; (void)buflen;
    *errnop = ENOENT;
    return NSS_STATUS_NOTFOUND;
}
