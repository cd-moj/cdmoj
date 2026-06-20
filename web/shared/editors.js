// shared/editors.js — editores/IDEs para o "editor favorito" do perfil.
// Os ids DEVEM casar com _valid_editor() em handlers/treino/profile.sh.
export const EDITORS = [
  { id: 'vscode', label: 'VS Code' }, { id: 'cursor', label: 'Cursor' },
  { id: 'vim', label: 'Vim' }, { id: 'neovim', label: 'Neovim (nvim)' },
  { id: 'emacs', label: 'Emacs' }, { id: 'nano', label: 'Nano' },
  { id: 'sublime', label: 'Sublime Text' }, { id: 'zed', label: 'Zed' },
  { id: 'helix', label: 'Helix' }, { id: 'micro', label: 'micro' },
  { id: 'notepadpp', label: 'Notepad++' },
  { id: 'intellij', label: 'IntelliJ IDEA' }, { id: 'pycharm', label: 'PyCharm' },
  { id: 'clion', label: 'CLion' }, { id: 'webstorm', label: 'WebStorm' },
  { id: 'goland', label: 'GoLand' }, { id: 'rider', label: 'Rider' },
  { id: 'phpstorm', label: 'PhpStorm' }, { id: 'rubymine', label: 'RubyMine' },
  { id: 'datagrip', label: 'DataGrip' }, { id: 'androidstudio', label: 'Android Studio' },
  { id: 'visualstudio', label: 'Visual Studio' }, { id: 'eclipse', label: 'Eclipse' },
  { id: 'xcode', label: 'Xcode' }, { id: 'codeblocks', label: 'Code::Blocks' },
  { id: 'geany', label: 'Geany' }, { id: 'kate', label: 'Kate' }, { id: 'gedit', label: 'gedit' },
  { id: 'other', label: 'Outro' },
];
export const editorLabel = (id) => (EDITORS.find((e) => e.id === id) || {}).label || id || '—';
