// Read only this widget's inline settings, preserving explicit false values.
function parse(text, id) {
    const config = JSON.parse(text);
    const layout = config && config.bar && config.bar.layout;
    if (!layout) return null;
    for (const section of ["left", "center", "right"]) {
        for (const entry of (Array.isArray(layout[section]) ? layout[section] : [])) {
            if (entry && entry.id === id) {
                const result = Object.assign({}, entry);
                delete result.id;
                return result;
            }
        }
    }
    return null;
}
if (typeof module !== "undefined") module.exports = {parse};
