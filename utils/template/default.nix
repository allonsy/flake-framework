{
  pkgs,
  lib,
  ...
}:
let
  placeholderPattern = "(\\\\?)\\{\\{([^{}]*)\\}\\}";

  keyPattern = "[[:space:]]*([^[:space:]]+)[[:space:]]*";

  knownKeys =
    context:
    let
      names = builtins.attrNames context;
    in
    if names == [ ] then "the context is empty" else "known keys: " + lib.concatStringsSep ", " names;

  valueToString =
    origin: key: value:
    if builtins.isInt value || lib.isStringLike value then
      toString value
    else
      throw "${origin}: value for key \"${key}\" is of type ${builtins.typeOf value}; expected a string, integer, path or derivation";

  substitute =
    origin: context: raw:
    let
      matched = builtins.match keyPattern raw;
    in
    if matched == null then
      throw "${origin}: malformed placeholder \"{{${raw}}}\"; expected a single key, as in {{ KEY }}, or \\{{ ... }} for a literal"
    else
      let
        key = builtins.head matched;
      in
      if builtins.hasAttr key context then
        valueToString origin key (builtins.getAttr key context)
      else
        throw "${origin}: no value for key \"${key}\"; ${knownKeys context}";

  renderPart =
    origin: context: part:
    if builtins.isString part then
      part
    else
      let
        escape = builtins.elemAt part 0;
        raw = builtins.elemAt part 1;
      in
      if escape == "\\" then "{{" + raw + "}}" else substitute origin context raw;

  render =
    origin: text: context:
    lib.concatStrings (map (renderPart origin context) (builtins.split placeholderPattern text));
in
{
  renderTemplate = template: context: render "renderTemplate" template context;

  writeTemplate =
    file: context:
    pkgs.writeText (baseNameOf (toString file)) (
      render "writeTemplate ${toString file}" (builtins.readFile file) context
    );
}
