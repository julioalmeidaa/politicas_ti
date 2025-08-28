#!/bin/bash

# Script de instalação automatizada para o Sistema de Geração de Políticas de TI
# Para Ubuntu 20.04

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar se o comando foi executado com sucesso
check_success() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$2"
        exit 1
    fi
}

# Verificar se é Ubuntu 20.04
if [ ! -f /etc/os-release ]; then
    print_error "Não foi possível detectar a distribuição do sistema."
    exit 1
fi

. /etc/os-release
if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "20.04" ]; then
    print_error "Este script é destinado apenas ao Ubuntu 20.04."
    exit 1
fi

# Verificar se é executado como root
if [ "$EUID" -ne 0 ]; then
    print_error "Por favor, execute este script como root ou com sudo."
    exit 1
fi

print_status "Iniciando a instalação do Sistema de Geração de Políticas de TI..."

# Atualizar sistema
print_status "Atualizando o sistema..."
apt update && apt upgrade -y
check_success "Sistema atualizado." "Falha ao atualizar o sistema."

# Instalar dependências do sistema
print_status "Instalando dependências do sistema..."
apt install -y curl git unzip libwpd-tools libwpg-tools libreoffice-writer
check_success "Dependências do sistema instaladas." "Falha ao instalar dependências do sistema."

# Instalar Node.js
print_status "Instalando Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
check_success "Node.js instalado." "Falha ao instalar Node.js."

# Verificar versões instaladas
print_status "Versões instaladas:"
node -v
npm -v

# Criar diretório do projeto
print_status "Criando diretório do projeto..."
PROJECT_DIR="/var/www/policy-generator"
mkdir -p $PROJECT_DIR
check_success "Diretório $PROJECT_DIR criado." "Falha ao criar diretório do projeto."

# Criar estrutura de pastas
print_status "Criando estrutura de pastas..."
mkdir -p $PROJECT_DIR/templates
mkdir -p $PROJECT_DIR/PDF
mkdir -p $PROJECT_DIR/Editaveis
mkdir -p $PROJECT_DIR/public
check_success "Estrutura de pastas criada." "Falha ao criar estrutura de pastas."

# Configurar permissões
print_status "Configurando permissões..."
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
check_success "Permissões configuradas." "Falha ao configurar permissões."

# Criar package.json
print_status "Criando package.json..."
cat > $PROJECT_DIR/package.json << 'EOL'
{
  "name": "policy-generator",
  "version": "1.0.0",
  "description": "Sistema de geração de políticas de TI",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "html-pdf": "^3.0.1",
    "html-docx-js": "^0.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOL
check_success "package.json criado." "Falha ao criar package.json."

# Instalar dependências do Node.js
print_status "Instalando dependências do Node.js..."
cd $PROJECT_DIR
npm install
check_success "Dependências do Node.js instaladas." "Falha ao instalar dependências do Node.js."

# Criar arquivo do servidor
print_status "Criando arquivo do servidor..."
cat > $PROJECT_DIR/server.js << 'EOL'
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
            border: {
                top: '1in',
                right: '1in',
                bottom: '1in',
                left: '1in'
            }
        };
        
        // Converter e salvar PDF
        const pdfPath = path.join('PDF', `${filenameBase}.pdf`);
        await new Promise((resolve, reject) => {
            htmlToPdf.create(htmlContent, pdfOptions).toFile(pdfPath, (err, result) => {
                if (err) reject(err);
                else resolve(result);
            });
        });
        
        // Converter e salvar DOCX
        const docxBuffer = htmlToDocx.asBlob(htmlContent);
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
        res.status(500).json({
            success: false,
            error: error.message
        });
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
EOL
check_success "Arquivo do servidor criado." "Falha ao criar arquivo do servidor."

# Criar arquivo HTML do frontend
print_status "Criando frontend..."

# Criar arquivo HTML principal
cat > $PROJECT_DIR/public/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IT ON BUSINESS - Gerador de Políticas de TI</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <div class="logo">
            <h1>IT ON BUSINESS</h1>
        </div>
        <nav class="nav-links">
            <a href="#"><i class="fas fa-home"></i> Início</a>
            <a href="#"><i class="fas fa-file-alt"></i> Modelos</a>
            <a href="#"><i class="fas fa-history"></i> Histórico</a>
            <a href="#"><i class="fas fa-user"></i> Área do Cliente</a>
        </nav>
    </header>
    
    <div class="container">
        <section class="hero">
            <h2>Gerador de Políticas de TI com Metodologias</h2>
            <p>Automatize a criação de documentos de políticas de TI baseados nas melhores práticas do mercado. Personalize, exporte e armazene em pastas locais.</p>
            
            <div class="methodology-tabs">
                <div class="methodology-tab active" data-method="all">Todas</div>
                <div class="methodology-tab" data-method="itil">ITIL</div>
                <div class="methodology-tab" data-method="cobit">COBIT</div>
                <div class="methodology-tab" data-method="iso">ISO 20000</div>
                <div class="methodology-tab" data-method="bsi">BSI</div>
            </div>
        </section>
        
        <section class="policy-grid">
            <div class="policy-card" data-methods="itil cobit">
                <div class="card-header">
                    <h3>Política de Uso de Tecnologia</h3>
                </div>
                <div class="card-body">
                    <p>Diretrizes para o uso adequado de recursos tecnológicos da empresa.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Uso de equipamentos</li>
                        <li><i class="fas fa-check-circle"></i> Acesso à internet</li>
                        <li><i class="fas fa-check-circle"></i> Redes sociais</li>
                        <li><i class="fas fa-check-circle"></i> Segurança da informação</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-itil">ITIL</span>
                        <span class="methodology-badge badge-cobit">COBIT</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn btn-itil" onclick="openModal('uso-tecnologia')">Criar Política</button>
                </div>
            </div>
            
            <div class="policy-card" data-methods="itil iso">
                <div class="card-header">
                    <h3>Procedimento de Mobilização</h3>
                </div>
                <div class="card-body">
                    <p>Processo para integração de novos colaboradores ao ambiente tecnológico.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Provisionamento de equipamentos</li>
                        <li><i class="fas fa-check-circle"></i> Acesso a sistemas</li>
                        <li><i class="fas fa-check-circle"></i> Treinamento inicial</li>
                        <li><i class="fas fa-check-circle"></i> Documentação necessária</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-itil">ITIL</span>
                        <span class="methodology-badge badge-iso">ISO 20000</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn btn-itil" onclick="openModal('mobilizacao')">Criar Procedimento</button>
                </div>
            </div>
            
            <div class="policy-card" data-methods="itil cobit bsi">
                <div class="card-header">
                    <h3>Procedimento de Desmobilização</h3>
                </div>
                <div class="card-body">
                    <p>Processo para desligamento de colaboradores do ambiente tecnológico.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Recolhimento de equipamentos</li>
                        <li><i class="fas fa-check-circle"></i> Revogação de acessos</li>
                        <li><i class="fas fa-check-circle"></i> Backup de dados</li>
                        <li><i class="fas fa-check-circle"></i> Documentação do processo</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-itil">ITIL</span>
                        <span class="methodology-badge badge-cobit">COBIT</span>
                        <span class="methodology-badge badge-bsi">BSI</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn btn-cobit" onclick="openModal('desmobilizacao')">Criar Procedimento</button>
                </div>
            </div>
            
            <div class="policy-card" data-methods="cobit iso bsi">
                <div class="card-header">
                    <h3>Política de Segurança</h3>
                </div>
                <div class="card-body">
                    <p>Diretrizes para proteção de dados e sistemas da empresa.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Senhas e autenticação</li>
                        <li><i class="fas fa-check-circle"></i> Proteção contra malware</li>
                        <li><i class="fas fa-check-circle"></i> Backup de dados</li>
                        <li><i class="fas fa-check-circle"></i> Resposta a incidentes</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-cobit">COBIT</span>
                        <span class="methodology-badge badge-iso">ISO 27001</span>
                        <span class="methodology-badge badge-bsi">BSI</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn btn-bsi" onclick="openModal('seguranca')">Criar Política</button>
                </div>
            </div>
        </section>
    </div>
    
    <!-- Modal para geração de políticas -->
    <div id="policyModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h2 id="modalTitle">Criar Política</h2>
                <span class="close" onclick="closeModal()">&times;</span>
            </div>
            
            <form id="policyForm">
                <div class="form-group">
                    <label for="companyName">Nome da Empresa</label>
                    <input type="text" id="companyName" required>
                </div>
                
                <div class="form-group">
                    <label for="sector">Setor de Atuação</label>
                    <select id="sector" required>
                        <option value="">Selecione o setor</option>
                        <option value="comercio">Comércio</option>
                        <option value="servicos">Serviços</option>
                        <option value="industria">Indústria</option>
                        <option value="tecnologia">Tecnologia</option>
                        <option value="saude">Saúde</option>
                        <option value="educacao">Educação</option>
                        <option value="financeiro">Financeiro</option>
                    </select>
                </div>
                
                <div class="form-group">
                    <label for="employees">Número de Funcionários</label>
                    <input type="number" id="employees" min="1" required>
                </div>
                
                <div style="display: flex; gap: 10px; margin-top: 20px;">
                    <button type="submit" class="btn"><i class="fas fa-save"></i> Salvar Documentos</button>
                </div>
            </form>
        </div>
    </div>
    
    <div id="notification" class="notification"></div>
    
    <footer>
        <p>IT ON BUSINESS &copy; 2023 - Todos os direitos reservados</p>
        <p>www.itonbusiness.com</p>
    </footer>
    
    <script src="app.js"></script>
</body>
</html>
HTMLEOF

# Criar arquivo CSS separado
cat > $PROJECT_DIR/public/styles.css << 'CSSEOF'
:root {
    --primary: #2c3e50;
    --secondary: #3498db;
    --accent: #e74c3c;
    --light: #ecf0f1;
    --dark: #2c3e50;
    --itil: #9b59b6;
    --cobit: #2ecc71;
    --iso: #f39c12;
    --bsi: #1abc9c;
    --success: #27ae60;
    --warning: #f39c12;
    --error: #e74c3c;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
}

body {
    background-color: #f5f7fa;
    color: #333;
    line-height: 1.6;
}

header {
    background: linear-gradient(135deg, var(--primary) 0%, var(--dark) 100%);
    color: white;
    padding: 1.5rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

.logo h1 {
    font-size: 1.5rem;
    font-weight: 600;
}

.nav-links {
    display: flex;
    gap: 20px;
}

.nav-links a {
    color: white;
    text-decoration: none;
    font-weight: 500;
    transition: opacity 0.3s;
}

.nav-links a:hover {
    opacity: 0.8;
}

.container {
    max-width: 1200px;
    margin: 2rem auto;
    padding: 0 1.5rem;
}

.hero {
    text-align: center;
    margin-bottom: 3rem;
    padding: 2rem;
    background: white;
    border-radius: 10px;
    box-shadow: 0 5px 15px rgba(0,0,0,0.05);
}

.hero h2 {
    font-size: 2.2rem;
    color: var(--primary);
    margin-bottom: 1rem;
}

.hero p {
    font-size: 1.1rem;
    color: #666;
    max-width: 800px;
    margin: 0 auto 1.5rem;
}

.methodology-tabs {
    display: flex;
    justify-content: center;
    flex-wrap: wrap;
    gap: 10px;
    margin: 2rem 0;
}

.methodology-tab {
    padding: 10px 20px;
    border-radius: 30px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    border: 2px solid transparent;
    background-color: var(--secondary);
    color: white;
}

.methodology-tab:hover {
    opacity: 0.8;
}

.policy-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 2rem;
    margin-bottom: 3rem;
}

.policy-card {
    background: white;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 4px 15px rgba(0,0,0,0.08);
    transition: transform 0.3s ease, box-shadow 0.3s ease;
    display: flex;
    flex-direction: column;
}

.policy-card:hover {
    transform: translateY(-5px);
    box-shadow: 0 8px 25px rgba(0,0,0,0.15);
}

.card-header {
    background-color: var(--secondary);
    color: white;
    padding: 1.2rem;
    text-align: center;
}

.card-body {
    padding: 1.5rem;
    flex-grow: 1;
}

.card-body ul {
    list-style-type: none;
    margin-bottom: 1.5rem;
}

.card-body li {
    padding: 0.5rem 0;
    border-bottom: 1px solid #eee;
    display: flex;
    align-items: center;
}

.card-body li i {
    margin-right: 10px;
    color: var(--secondary);
}

.methodology-badge {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 4px;
    font-size: 0.8rem;
    font-weight: 600;
    margin: 5px 5px 5px 0;
    color: white;
}

.badge-itil {
    background-color: var(--itil);
}

.badge-cobit {
    background-color: var(--cobit);
}

.badge-iso {
    background-color: var(--iso);
}

.badge-bsi {
    background-color: var(--bsi);
}

.card-footer {
    padding: 1rem 1.5rem;
    background-color: #f9f9f9;
    border-top: 1px solid #eee;
    text-align: center;
}

.btn {
    display: inline-block;
    background-color: var(--secondary);
    color: white;
    padding: 0.8rem 1.5rem;
    border-radius: 4px;
    text-decoration: none;
    font-weight: 600;
    transition: background-color 0.3s ease;
    border: none;
    cursor: pointer;
}

.btn:hover {
    background-color: var(--primary);
}

.modal {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-color: rgba(0,0,0,0.5);
    z-index: 1000;
    justify-content: center;
    align-items: center;
    padding: 1rem;
}

.modal-content {
    background-color: white;
    padding: 2rem;
    border-radius: 8px;
    width: 90%;
    max-width: 600px;
    max-height: 90vh;
    overflow-y: auto;
    box-shadow: 0 5px 30px rgba(0,0,0,0.2);
}

.form-group {
    margin-bottom: 1.5rem;
}

.form-group label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: 600;
}

.form-group input, .form-group select {
    width: 100%;
    padding: 0.8rem;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 1rem;
}

.modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1.5rem;
    padding-bottom: 1rem;
    border-bottom: 1px solid #eee;
}

.close {
    font-size: 1.5rem;
    cursor: pointer;
    color: #999;
}

.close:hover {
    color: #333;
}

.notification {
    position: fixed;
    top: 20px;
    right: 20px;
    padding: 15px 20px;
    border-radius: 5px;
    color: white;
    font-weight: 600;
    z-index: 1000;
    opacity: 0;
    transform: translateY(-20px);
    transition: opacity 0.3s, transform 0.3s;
}

.notification.show {
    opacity: 1;
    transform: translateY(0);
}

.notification.success {
    background-color: var(--success);
}

.notification.error {
    background-color: var(--error);
}

footer {
    background-color: var(--dark);
    color: white;
    text-align: center;
    padding: 2rem;
    margin-top: 3rem;
}

@media (max-width: 768px) {
    .policy-grid {
        grid-template-columns: 1fr;
    }
    
    .hero h2 {
        font-size: 1.8rem;
    }
    
    .nav-links {
        display: none;
    }
}
CSSEOF

# Criar arquivo JavaScript separado
cat > $PROJECT_DIR/public/app.js << 'JSEOF'
let currentPolicyType = '';

const policies = {
    'uso-tecnologia': {
        title: 'Política de Uso de Tecnologia'
    },
    'mobilizacao': {
        title: 'Procedimento de Mobilização'
    },
    'desmobilizacao': {
        title: 'Procedimento de Desmobilização'
    },
    'seguranca': {
        title: 'Política de Segurança da Informação'
    }
};

function openModal(policyType) {
    currentPolicyType = policyType;
    const policy = policies[policyType];
    const modal = document.getElementById('policyModal');
    const title = document.getElementById('modalTitle');
    
    title.textContent = policy.title;
    modal.style.display = 'flex';
}

function closeModal() {
    document.getElementById('policyModal').style.display = 'none';
    document.getElementById('policyForm').reset();
}

function showNotification(message, type) {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.className = `notification ${type} show`;
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}

async function saveToServer(policyData) {
    try {
        const response = await fetch('/api/save-policy', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                policyData,
                htmlContent: `<h1>${policyData.title}</h1><p>Empresa: ${policyData.companyName}</p>`
            })
        });
        
        const result = await response.json();
        return result;
    } catch (error) {
        throw new Error('Erro de conexão com o servidor: ' + error.message);
    }
}

document.getElementById('policyForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const formData = {
        companyName: document.getElementById('companyName').value,
        sector: document.getElementById('sector').value,
        employees: document.getElementById('employees').value,
        title: policies[currentPolicyType].title,
        type: currentPolicyType
    };
    
    try {
        const result = await saveToServer(formData);
        
        if (result.success) {
            showNotification(result.message, 'success');
            setTimeout(() => {
                closeModal();
            }, 2000);
        } else {
            throw new Error(result.error);
        }
    } catch (error) {
        showNotification(error.message, 'error');
    }
});

window.addEventListener('click', function(e) {
    const modal = document.getElementById('policyModal');
    if (e.target === modal) {
        closeModal();
    }
});

document.querySelectorAll('.methodology-tab').forEach(tab => {
    tab.addEventListener('click', function() {
        const method = this.getAttribute('data-method');
        
        document.querySelectorAll('.methodology
