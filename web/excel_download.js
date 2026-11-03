// web/excel_download.js
// Funciones para guardar archivos Excel desde Flutter Web

let pickedExcelFileHandle = null;

async function pickExcelFile(filename) {
  if (!window.showSaveFilePicker) return 'unsupported';

  try {
    pickedExcelFileHandle = await window.showSaveFilePicker({
      id: 'finanzas-excel',
      suggestedName: filename,
      types: [{
        description: 'Excel Workbook',
        accept: {
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ['.xlsx']
        }
      }]
    });
    return 'picked';
  } catch (e) {
    if (e && e.name === 'AbortError') return 'cancelled';
    return 'error';
  }
}

async function writeExcelToPickedFile(bytes) {
  if (!pickedExcelFileHandle) return 'error';

  try {
    const writable = await pickedExcelFileHandle.createWritable();
    await writable.write(new Uint8Array(bytes));
    await writable.close();
    return 'saved';
  } catch (e) {
    return 'error';
  } finally {
    pickedExcelFileHandle = null;
  }
}

function cancelPickedFile() {
  pickedExcelFileHandle = null;
}

function downloadExcelFile(bytes, filename) {
  const blob = new Blob([new Uint8Array(bytes)], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
