const express = require('express');
const cors = require('cors');
const fs = require('fs').promises;
const path = require('path');
const htmlToPdf = require('html-pdf');
const htmlToDocx = require('html-docx-js');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.static('public'));

// Rotas
app.post('/api/save-policy', async (req, res) => {
  try {
    const { policyData, htmlContent } = req.body;

    // Criar diretórios se não existirem
    await fs.mkdir('templates', { recursive: true });
    await fs.mkdir('PDF', { recursive: true });
    await fs.mkdir('Editaveis', { recursive: true });

    // Gerar nome de arquivo seguro
    const safeCompanyName = policyData.companyName.replace(/[^a-z0-9]/gi, '_').toLowerCase();
    const safePolicyName = policyData.title.replace(/[^a-z0-9]/gi, '_').toLowerCase();
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filenameBase = `${safeCompanyName}_${safePolicyName}_${timestamp}`;

    // Salvar template HTML
    const templatePath = path.join('templates', `${filenameBase}.html`);
    await fs.writeFile(templatePath, htmlContent);

    // Configurações para o PDF
    const pdfOptions = {
      format: 'A4',
      border: { top: '1in', right: '1in', bottom: '1in', left: '1in' }
    };

    // Converter e salvar PDF
    const pdfPath = path.join('PDF', `${filenameBase}.pdf`);
    await new Promise((resolve, reject) => {
      htmlToPdf.create(htmlContent, pdfOptions).toFile(pdfPath, (err, result) => {
        if (err) reject(err);
        else resolve(result);
      });
    });

    // Converter e salvar DOCX (correção: usar asBuffer)
    const docxBuffer = htmlToDocx.asBuffer(htmlContent);
    const docxPath = path.join('Editaveis', `${filenameBase}.docx`);
    await fs.writeFile(docxPath, docxBuffer);

    res.json({
      success: true,
      message: 'Documentos salvos com sucesso!',
      paths: {
        template: templatePath,
        pdf: pdfPath,
        docx: docxPath
      }
    });
  } catch (error) {
    console.error('Erro ao salvar documentos:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Rota para listar políticas salvas
app.get('/api/policies', async (req, res) => {
  try {
    const policies = [];
    // Ler arquivos PDF
    try {
      const pdfFiles = await fs.readdir('PDF');
      pdfFiles.forEach(file => {
        if (file.endsWith('.pdf')) {
          policies.push({
            name: file,
            type: 'pdf',
            path: path.join('PDF', file),
            created: fs.statSync(path.join('PDF', file)).mtime
          });
        }
      });
    } catch (error) {
      console.log('Nenhum arquivo PDF encontrado');
    }
    res.json({ success: true, policies });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Rota padrão para servir o frontend
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Iniciar servidor
app.listen(port, () => {
  console.log(`Servidor rodando na porta ${port}`);
  console.log(`Acesse: http://localhost:${port}`);
});
