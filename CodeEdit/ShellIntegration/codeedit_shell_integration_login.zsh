# Modified from Microsoft's VSCode. MIT License.
# Permalink to original file:
# https://github.com/microsoft/vscode/blob/60d7343892f10e0c5f09cb55a6a3f268eb0dd4fb/src/vs/workbench/contrib/terminal/browser/media/shellIntegration-login.zsh

ZDOTDIR=$USER_ZDOTDIR
if [[ -o "login" &&  -f $ZDOTDIR/.zlogin ]]; then
	. $ZDOTDIR/.zlogin
fi

# Re-prepend the project's runtime PATH (after the user's .zlogin has run).
if [[ -n "$CE_RUNTIME_PATH" && "$PATH" != "$CE_RUNTIME_PATH:"* ]]; then
	export PATH="$CE_RUNTIME_PATH:$PATH"
fi
