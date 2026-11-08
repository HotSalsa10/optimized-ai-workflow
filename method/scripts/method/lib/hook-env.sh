# shellcheck shell=bash
# hook-env.sh: sourced by the method's hooks just before they start perl
# (step 5.5). It removes every exported PERL* variable (PERL5OPT, PERL5LIB,
# PERLLIB, PERL5DB, PERLIO, PERL_UNICODE and the rest), which a settings
# file could set to change what the hooks' perl runs or reads. compgen is a
# bash builtin, so no program starts for it. The hooks then start perl as
# "command perl", so a shell function named perl cannot stand in for it.
for _hook_env_name in $(compgen -e); do
  case $_hook_env_name in
    PERL*) unset "$_hook_env_name" ;;
  esac
done
unset _hook_env_name
# PATH keeps only absolute folders: an empty or relative entry (".", "bin")
# would let a perl written into the project stand in for the real one
_hook_env_path=
_hook_env_rest=$PATH:
while [ -n "$_hook_env_rest" ]; do
  _hook_env_dir=${_hook_env_rest%%:*}
  _hook_env_rest=${_hook_env_rest#*:}
  case $_hook_env_dir in
    /*) _hook_env_path=${_hook_env_path:+$_hook_env_path:}$_hook_env_dir ;;
  esac
done
PATH=$_hook_env_path
export PATH
unset _hook_env_path _hook_env_rest _hook_env_dir
