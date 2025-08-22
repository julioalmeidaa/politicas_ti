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
cat > $PROJECT_DIR/public/index.html << 'EOL'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IT ON BUSINESS - Gerador de Políticas de TI</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
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
            position: sticky;
            top: 0;
            z-index: 100;
        }
        
        .logo {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .logo img {
            height: 40px;
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
        }
        
        .methodology-tab.active {
            color: white;
        }
        
        .methodology-tab[data-method="itil"] {
            background-color: var(--itil);
            color: white;
        }
        
        .methodology-tab[data-method="cobit"] {
            background-color: var(--cobit);
            color: white;
        }
        
        .methodology-tab[data-method="iso"] {
            background-color: var(--iso);
            color: white;
        }
        
        .methodology-tab[data-method="bsi"] {
            background-color: var(--bsi);
            color: white;
        }
        
        .methodology-tab:hover:not(.active) {
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
        
        .card-body li:last-child {
            border-bottom: none;
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
        
        .btn-outline {
            background-color: transparent;
            border: 2px solid var(--secondary);
            color: var(--secondary);
        }
        
        .btn-outline:hover {
            background-color: var(--secondary);
            color: white;
        }
        
        .btn-itil {
            background-color: var(--itil);
        }
        
        .btn-cobit {
            background-color: var(--cobit);
        }
        
        .btn-iso {
            background-color: var(--iso);
        }
        
        .btn-bsi {
            background-color: var(--bsi);
        }
        
        .btn-success {
            background-color: var(--success);
        }
        
        .btn-error {
            background-color: var(--error);
        }
        
        footer {
            background-color: var(--dark);
            color: white;
            text-align: center;
            padding: 2rem;
            margin-top: 3rem;
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
            max-width: 800px;
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
        
        .form-group input, .form-group select, .form-group textarea {
            width: 100%;
            padding: 0.8rem;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 1rem;
        }
        
        .form-group textarea {
            min-height: 120px;
            resize: vertical;
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
        
        .methodology-info {
            background-color: #f8f9fa;
            padding: 1rem;
            border-radius: 6px;
            margin-bottom: 1.5rem;
            border-left: 4px solid var(--secondary);
        }
        
        .preview-container {
            border: 1px solid #ddd;
            border-radius: 6px;
            padding: 1.5rem;
            margin-top: 1.5rem;
            background-color: #f9f9f9;
            max-height: 300px;
            overflow-y: auto;
        }
        
        .preview-header {
            text-align: center;
            margin-bottom: 1rem;
            padding-bottom: 1rem;
            border-bottom: 2px solid #ddd;
        }
        
        .storage-config {
            background-color: #f8f9fa;
            padding: 1.5rem;
            border-radius: 8px;
            margin: 1.5rem 0;
            border-left: 4px solid var(--secondary);
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
            box-shadow: 0 4px極限
EOL

# Continuar o arquivo HTML (parte 2)
cat >> $PROJECT_DIR/public/index.html << 'EOL'
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
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
        
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            border-left: 4px solid var(--secondary);
            border-radius: 50%;
            width: 30px;
            height: 30px;
            animation: spin 1s linear infinite;
            margin: 0 auto;
            display: none;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
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
    </style>
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
                    <p>Diretrizes para proteção de dados de sistemas da empresa.</p>
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
            
            <div class="policy-card" data-methods="itil cobit">
                <div class="card-header">
                    <h3>Política de Backup</h3>
                </div>
                <div class="card-body">
                    <p>Diretrizes para cópia de segurança de dados corporativos.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Frequência de backup</li>
                        <li><i class="fas fa-check-circle"></i> Tipos de backup</li>
                        <li><i class="fas fa-check-circle"></i> Armazenamento</li>
                        <li><i class="fas fa-check-circle"></i> Testes de recuperação</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-itil">ITIL</span>
                        <span class="methodology-badge badge-cobit">COBIT</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn" onclick="openModal('backup')">Criar Política</button>
                </div>
            </div>
            
            <div class="policy-card" data-methods="itil cobit iso">
                <div class="card-header">
                    <h3>Política de Uso de E-mail</h3>
                </div>
                <div class="card-body">
                    <p>Diretrizes para uso adequado do correio eletrônico corporativo.</p>
                    <ul>
                        <li><i class="fas fa-check-circle"></i> Uso apropriado</li>
                        <li><i class="fas fa-check-circle"></i> Segurança</li>
                        <li><i class="fas fa-check-circle"></i> Retenção de mensagens</li>
                        <li><i class="fas fa-check-circle"></i> Monitoramento</li>
                    </ul>
                    <div>
                        <span class="methodology-badge badge-itil">ITIL</span>
                        <span class="methodology-badge badge-cobit">COBIT</span>
                        <span class="methodology-badge badge-iso">ISO 20000</span>
                    </div>
                </div>
                <div class="card-footer">
                    <button class="btn btn-iso" onclick="openModal('email')">Criar Política</button>
                </div>
            </div>
        </section>
    </div>
    
    <footer>
        <p>IT ON BUSINESS &copy; 2023 - Todos os direitos reservados</p>
        <p>www.itonbusiness.com</p>
    </footer>
    
    <!-- Modal para geração de políticas -->
    <div id="policyModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h2 id="modalTitle">Criar Política</h2>
                <span class="close" onclick="closeModal()">&times;</span>
            </div>
            
            <div class="methodology-info">
                <h3 id="methodologyName">Metodologias Aplicadas</h3>
                <p id="methodologyDescription">Esta política incorpora as melhores práticas das metodologias selecionadas.</p>
            </div>
            
            <div class="storage-config">
                <h3><i class="fas fa-folder"></i> Estrutura de Armazenamento</h3>
                <p>Os documentos serão salvos nas seguintes pastas do servidor:</p>
                <ul>
                    <li><strong>templates/</strong> - Modelos de políticas</li>
                    <li><strong>PDF/</strong> - Documentos finais em PDF</li>
                    <li><strong>Editaveis/</strong> - Documentos em DOCX para edição</li>
                </ul>
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
                
                <div class="form-group">
                    <label for="complianceLevel">Nível de Conformidade Requerido</label>
                    <select id="complianceLevel">
                        <option value="basico">Básico</option>
                        <option value="intermediario">Intermediário</option>
                        <option value="avancado">Avançado</option>
                        <option value="rigoroso">Rigoroso</option>
                    </select>
                </div>
                
                <div class="form-group">
                    <label for="specificRules">Regras Específicas (opcional)</label>
                    <textarea id="specificRules" placeholder="Informe regras ou diretrizes específicas que devem ser incluídas na política..."></textarea>
                </div>
                
                <div class="form-group">
                    <label for="contact">Responsável pela Aprovação</label>
                    <input type="text" id="contact" required>
                </div>
                
                <div class="preview-container">
                    <div class="preview-header">
                        <h3>Pré-visualização da Política</h3>
                    </div>
                    <div id="policyPreview">
                        <p>Preencha os campos acima para visualizar a política.</p>
                    </div>
                </div>
                
                <div id="spinner" class="spinner"></div>
                
                <div style="display: flex; gap: 10px; margin-top: 20px;">
                    <button type="submit" class="btn"><i class="fas fa-save"></i> Salvar Documentos</button>
                    <button type="button" class="btn btn-outline" onclick="downloadPolicy()"><i class="fas fa-download"></i> Exportar para PDF</button>
                </div>
            </form>
        </div>
    </div>
    
    <div id="notification" class="notification"></div>
    
    <script>
        let currentPolicyType = '';
        let currentMethodologies = [];
        
        // Dados sobre metodologias
        const methodologies = {
            itil: {
                name: "ITIL (Information Technology Infrastructure Library)",
                description: "Conjunto de melhores práticas para gerenciamento de serviços de TI focado no alinhamento entre TI e negócios."
            },
            cobit: {
                name: "COBIT (Control Objectives for Information and Related Technologies)",
                description: "Framework de governança de TI que ajuda na gestão de riscos e compliance."
            },
            iso: {
                name: "ISO/IEC 20000",
                description: "Padrão internacional para gestão de serviços de TI, especificando requisitos para planejamento, desenho, transição, entrega e melhoria de serviços."
            },
            bsi: {
                name: "BSI (British Standards Institution)",
                description: "Conjunto de padrões britânicos para gestão de serviços de TI, incluindo a ITIL."
            }
        };
        
        // Dados das políticas
        const policies = {
            'uso-tecnologia': {
                title: 'Política de Uso de Tecnologia',
                methodologies: ['itil', 'cobit'],
                template: (data) => `
                    <h2>Política de Uso de Tecnologia - ${data.companyName}</h2>
                    <p><strong>Setor:</strong> ${data.sector}</p>
                    <p><strong>Número de funcionários:</strong> ${data.employees}</p>
                    <p><strong>Nível de conformidade:</strong> ${data.complianceLevel}</p>
                    
                    <h3>1. Objetivo</h3>
                    <p>Estabelecer diretrizes para o uso adequado dos recursos tecnológicos da empresa ${data.companyName}.</p>
                    
                    <h3>2. Escopo</h3>
                    <p>Esta política aplica-se a todos os colaboradores, estagiários, terceiros e prestadores de serviços que utilizem os recursos de TI da empresa.</p>
                    
                    <h3>3. Diretrizes de Uso</h3>
                    <p>3.1. Os equipamentos de TI são de propriedade da empresa e devem ser utilizados principalmente para fins profissionais.</p>
                    <p>3.2. O uso de internet está sujeito a monitoramento para garantir a segurança dos dados corporativos.</p>
                    <p>3.3. O acesso a redes sociais é permitido durante horários de intervalo, desde que não interfira na produtividade.</p>
                    
                    <h3>4. Metodologias Aplicadas</h3>
                    <p>Esta política foi desenvolvida com base nas melhores práticas do ITIL e COBIT, garantindo alinhamento com os objetivos de negócio e conformidade com requisitos de governança.</p>
                `
            },
            'mobilizacao': {
                title: 'Procedimento de Mobilização de Colaboradores',
                methodologies: ['itil', 'iso'],
                template: (data) => `
                    <h2>Procedimento de Mobilização - ${data.companyName}</h2>
                    <p>Este documento estabelece o processo para integração de novos colaboradores ao ambiente tecnológico.</p>
                    
                    <h3>1. Provisionamento de Equipamentos</h3>
                    <p>Todo novo colaborador receberá equipamento de acordo com sua função, pré-configurado com software necessário.</p>
                    
                    <h3>2. Acesso a Sistemas</h3>
                    <p>Os acessos serão provisionados com base no princípio do menor privilégio, garantindo apenas as permissões necessárias.</p>
                    
                    <h3>3. Metodologias Aplicadas</h3>
                    <p>Este procedimento seguirá as melhores práticas de ITIL para Gestão de Acesso e ISO 20000 para padronização de processos.</p>
                `
            },
            'desmobilizacao': {
                title: 'Procedimento de Desmobilização de Colaboradores',
                methodologies: ['itil', 'cobit', 'bsi'],
                template: (data) => `
                    <h2>Procedimento de Desmobilização - ${data.companyName}</h2>
                    <p>Este documento estabelece o processo para desligamento de colaboradores do ambiente tecnológico.</p>
                    
                    <h3>1. Recolhimento de Equipamentos</h3>
                    <p>Todo equipamento da empresa deve ser devolvido no último dia de trabalho do colaborador.</p>
                    
                    <h3>2. Revogação de Acessos</h3>
                    <p>Todos os acessos a sistemas e aplicações serão revogados imediatamente após o desligamento.</p>
                    
                    <h3>3. Metodologias Aplicadas</h3>
                    <p>Este procedimento seguirá as melhores práticas de ITIL, COBIT и BSI para gestão de acessos e segurança da informação.</p>
                `
            },
            'seguranca': {
                title: 'Política de Segurança da Informação',
                methodologies: ['cobit', 'iso', 'bsi'],
                template: (data) => `
                    <h2>Política de Segurança da Informação - ${data.companyName}</h2>
                    <p><strong>Setor:</strong> ${data.sector}</p>
                    <p><strong>Número de funcionários:</strong> ${data.employees}</p>
                    <p><strong>Nível de conformidade:</strong> ${data.complianceLevel}</p>
                    
                    <h3>1. Objetivo</h3>
                    <p>Estabelecer diretrizes para proteção dos ativos de informação da empresa ${data.companyName}.</p>
                    
                    <h3>2. Escopo</h3>
                    <p>Esta política aplica-se a todos os colaboradores, sistemas de informação, dados e processos de negócio da empresa.</p>
                    
                    <h3>3. Diretrizes de Segurança</h3>
                    <p>3.1. Todos os usuários devem utilizar senhas complexas e alterá-las periodicamente.</p>
                    <p>3.2. É proibido instalar software não autorizado nos equipamentos da empresa.</p>
                    <p>3.3. Todos os dispositivos móveis devem estar protegidos with criptografia.</p>
                    
                    <h3>4. Metodologias Aplicadas</h3>
                    <p>Esta política foi desenvolvida com base nas melhores práticas do COBIT, ISO 27001 e BSI, garantindo a conformidade com padrões internacionais de segurança.</p>
                `
            },
            'backup': {
                title: 'Política de Backup e Recuperação',
                methodologies: ['itil', 'cobit'],
                template: (data) => `
                    <h2>Política de Backup e Recuperação - ${data.companyName}</h2>
                    <p>Este documento estabelece as diretrizes para cópia de segurança e recuperação de dados corporativos.</p>
                    
                    <h3>1. Frequência de Backup</h3>
                    <p>Backups completos devem ser realizados semanalmente, com backups incrementais diários.</p>
                    
                    <h3>2. Retenção de Dados</h3>
                    <p>Os backups devem ser mantidos por um período mínimo de 90 dias.</p>
                    
                    <h極限
EOL

# Continuar o arquivo HTML (parte 3 - final)
cat >> $PROJECT_DIR/public/index.html << 'EOL'
                    <h3>3. Testes de Recuperação</h3>
                    <p>Testes de recuperação devem ser realizados trimestralmente para garantir a integridade dos backups.</p>
                `
            },
            'email': {
                title: 'Política de Uso de E-mail Corporativo',
                methodologies: ['itil', 'cobit', 'iso'],
                template: (data) => `
                    <h2>Política de Uso de E-mail Corporativo - ${data.companyName}</h2>
                    <p>Este documento estabelece as diretrizes para o uso adequado do correio eletrônico corporativo.</p>
                    
                    <h極限
EOL

# Finalizar o arquivo HTML
cat >> $PROJECT_DIR/public/index.html << 'EOL'
                    <h3>1. Uso Apropriado</h3>
                    <p>O e-mail corporativo deve ser utilizado principalmente para assuntos relacionados ao trabalho.</p>
                    
                    <h3>2. Segurança</h3>
                    <p>É proibido abrir anexos de remetentes desconhecidos ou clicar em links suspeitos.</p>
                    
                    <h3>3. Retenção de Mensagens</h3>
                    <p>As mensagens de e-mail serão retidas por um período de 12 meses, de acordo com a política de compliance da empresa.</p>
                `
            }
        };
        
        function openModal(policyType) {
            currentPolicyType = policyType;
            const policy = policies[policyType];
            const modal = document.getElementById('policyModal');
            const title = document.getElementById('modalTitle');
            const methodName = document.getElementById('methodologyName');
            const methodDesc = document.getElementById('methodologyDescription');
            
            title.textContent = policy.title;
            
            // Atualizar informações sobre metodologias
            currentMethodologies = policy.methodologies;
            methodName.textContent = currentMethodologies.map(m => methodologies[m].name).join(' e ');
            methodDesc.textContent = currentMethodologies.map(m => methodologies[m].description).join(' ');
            
            modal.style.display = 'flex';
            updatePolicyPreview();
        }
        
        function closeModal() {
            document.getElementById('policyModal').style.display = 'none';
            document.getElementById('policyForm').reset();
        }
        
        function updatePolicyPreview() {
            if (!currentPolicyType) return;
            
            const formData = {
                companyName: document.getElementById('companyName').value || '[Nome da Empresa]',
                sector: document.getElementById('sector').value || '[Setor]',
                employees: document.getElementById('employees').value || '[Número de Funcionários]',
                complianceLevel: document.getElementById('complianceLevel').value || '[Nível de Conformidade]',
                specificRules: document.getElementById('specificRules').value || ''
            };
            
            const policy = policies[currentPolicyType];
            document.getElementById('policyPreview').innerHTML = policy.template(formData);
        }
        
        function downloadPolicy() {
            alert('Funcionalidade de exportação para PDF será implementada aqui. Em uma aplicação real, isso geraria um documento PDF para download.');
            // Em uma implementação real, usaria bibliotecas como jsPDF ou html2pdf.js
        }
        
        function showNotification(message, type) {
            const notification = document.getElementById('notification');
            notification.textContent = message;
            notification.className = `notification ${type} show`;
            
            setTimeout(() => {
                notification.classList.remove('show');
            }, 3000);
        }
        
        function showSpinner(show) {
            document.getElementById('spinner').style.display = show ? 'block' : 'none';
        }
        
        // Função para salvar no servidor
        async function saveToServer(policyData, htmlContent) {
            try {
                const response = await fetch('/api/save-policy', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        policyData,
                        htmlContent
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
            
            // Coletar dados do formulário
            const formData = {
                companyName: document.getElementById('companyName').value,
                sector: document.getElementById('sector').value,
                employees: document.getElementById('employees').value,
                complianceLevel: document.getElementById('complianceLevel').value,
                specificRules: document.getElementById('specificRules').value,
                contact: document.getElementById('contact').value,
                title: policies[currentPolicyType].title,
                type: currentPolicyType
            };
            
            // Obter conteúdo HTML para salvar como template
            const htmlContent = document.getElementById('policyPreview').innerHTML;
            
            // Mostrar spinner de carregamento
            showSpinner(true);
            
            try {
                // Salvar no servidor
                const result = await saveToServer(formData, htmlContent);
                
                if (result.success) {
                    // Mostrar mensagem de sucesso com os caminhos
                    showNotification(result.message, 'success');
                    
                    // Em uma implementação real, aqui poderíamos mostrar os caminhos dos arquivos
                    console.log("Arquivos salvos em:", result.paths);
                } else {
                    throw new Error(result.error);
                }
                
                // Fechar o modal após o sucesso
                setTimeout(() => {
                    closeModal();
                    showSpinner(false);
                }, 2000);
                
            } catch (error) {
                // Mostrar mensagem de erro
                showNotification(error.message, 'error');
                showSpinner(false);
            }
        });
        
        // Adicionar event listeners para atualizar a pré-visualização
        document.getElementById('companyName').addEventListener('input', updatePolicyPreview);
        document.getElementById('sector').addEventListener('change', updatePolicyPreview);
        document.getElementById('employees').addEventListener('input', updatePolicyPreview);
        document.getElementById('complianceLevel').addEventListener('change', updatePolicyPreview);
        document.getElementById('specificRules').addEventListener('input', updatePolicyPreview);
        
        // Fechar modal clicando fora dele
        window.addEventListener('click', function(e) {
            const modal = document.getElementById('policyModal');
            if (e.target === modal) {
                closeModal();
            }
        });
        
        // Filtrar políticas por metodologia
        document.querySelectorAll('.methodology-tab').forEach(tab => {
            tab.addEventListener('click', function() {
                const method = this.getAttribute('data-method');
                
                // Atualizar aba ativa
                document.querySelectorAll('.methodology-tab').forEach(t => t.classList.remove('active'));
                this.classList.add('active');
                
                // Filtrar cards
                document.querySelectorAll('.policy-card').forEach(card => {
                    if (method === 'all') {
                        card.style.display = 'flex';
                    } else {
                        const methods = card.getAttribute('data-methods');
                        if (methods.includes(method)) {
                            card.style.display = 'flex';
                        } else {
                            card.style.display = 'none';
                        }
                    }
                });
            });
        });
    </script>
</body>
</html>
EOL
check_success "Frontend criado." "Falha ao criar frontend."

# Instalar PM2 globalmente
print_status "Instalando PM2..."
npm install -g pm2
check_success "PM2 instalado." "Falha ao instalar PM2."

# Iniciar aplicação com PM2
print_status "Iniciando aplicação com PM2..."
cd $PROJECT_DIR
pm2 start server.js --name policy-generator
check_success "Aplicação iniciada com PM2." "Falha ao iniciar aplicação com PM2."

# Configurar PM2 para iniciar com o sistema
print_status "Configurando PM2 para iniciar com o sistema..."
pm2 startup
pm2 save
check_success "PM2 configurado para iniciar com o sistema." "Falha ao configurar PM2."

# Instalar e configurar Nginx
print_status "Instalando e configurando Nginx..."
apt install -y nginx

# Criar configuração do Nginx
cat > /etc/nginx/sites-available/policy-generator << 'EOL'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOL

# Habilitar site
ln -s /etc/nginx/sites-available/policy-generator /etc/nginx/sites-enabled/

# Testar configuração do Nginx
nginx -t
check_success "Configuração do Nginx testada com sucesso." "Falha na configuração do Nginx."

# Reiniciar Nginx
systemctl restart nginx
check_success "Nginx reiniciado." "Falha ao reiniciar Nginx."

# Configurar firewall
print_status "Configurando firewall..."
ufw allow 'Nginx Full'
check_success "Firewall configurado." "Falha ao configurar firewall."

# Testar aplicação
print_status "Testando aplicação..."
sleep 3
curl -s http://localhost:3000 > /dev/null
if [ $? -eq 0 ]; then
    print_success "Aplicação está funcionando corretamente."
else
    print_warning "A aplicação pode não estar respondendo. Verifique com: systemctl status nginx && pm2 status"
fi

# Informações finais
print_success "Instalação concluída com sucesso!"
echo ""
echo "=================================================="
echo "         SISTEMA INSTALADO COM SUCESSO"
echo "=================================================="
echo "URL de acesso: http://$(curl -s ifconfig.me)"
echo "URL local: http://localhost:3000"
echo "Diretório de instalação: $PROJECT_DIR"
echo "Pastas criadas:"
echo "  - $PROJECT_DIR/templates (Modelos HTML)"
echo "  - $PROJECT_DIR/PDF (Documentos PDF)"
echo "  - $PROJECT_DIR/Editaveis (Documentos DOCX)"
echo ""
echo "Comandos úteis:"
echo "  - Reiniciar aplicação: pm2 restart policy-generator"
echo "  - Ver logs: pm2 logs policy-generator"
echo "  - Ver status: pm2 status"
echo "  - Ver status do Nginx: systemctl status nginx"
echo "=================================================="

exit 0