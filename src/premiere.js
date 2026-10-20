/* global require */

const PremiereBridge = (() => {
  function app() {
    return require("premierepro");
  }

  async function getActiveProject() {
    return app().Project.getActiveProject();
  }

  async function getDestinationName() {
    const project = await getActiveProject();
    const insertionBin = await project.getInsertionBin() || await project.getRootItem();
    return insertionBin && insertionBin.name ? insertionBin.name : project.name;
  }

  async function importFile(filePath) {
    if (!filePath) {
      throw new Error("VIDLOAD Engine did not return a file path.");
    }

    const project = await getActiveProject();
    const insertionBin = await project.getInsertionBin() || await project.getRootItem();
    const imported = await project.importFiles([filePath], true, insertionBin, false);

    if (!imported) {
      throw new Error("Premiere Pro could not add the file to this project.");
    }

    return { projectName: project.name, binName: insertionBin && insertionBin.name ? insertionBin.name : project.name };
  }

  return { getDestinationName, importFile };
})();
