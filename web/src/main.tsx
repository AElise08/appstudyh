import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./app/App";
import "./styles/app.css";

const rootElement = document.getElementById("root");
if (rootElement === null) throw new Error("elemento #root não encontrado");

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
