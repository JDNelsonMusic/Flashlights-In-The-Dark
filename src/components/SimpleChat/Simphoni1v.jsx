import React, { useState, useRef, useEffect, useCallback } from 'react';
import useNavProps from '@/hooks/useNavProps';
import {
  runSingleInference,
  runVisionInference,
  runOpenAIInference,
  runWhisperTranscription,
  runTextToSpeech,
  runAudioGeneration,
} from '@/services/inference';
import { renderChart } from '@/utils/charts';
import simphoniLogo from '/official_simphoni_geometry_favicon.png';
import { FaPlus, FaMicrophone, FaWaveSquare } from 'react-icons/fa';
import './Simphoni1v.css';

function Simphoni1v() {
  const [messages, setMessages] = useState([]);
  const [userInput, setUserInput] = useState('');
  const [attachments, setAttachments] = useState([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [savePrompt, setSavePrompt] = useState(null);
  const abortControllerRef = useRef(null);
  const fileInputRef = useRef(null);
  const nav = useNavProps();

  // Hide global navigation and sidebars
  useEffect(() => {
    nav?.set?.({ show: false });
  }, [nav]);

  const detectModel = useCallback((msg) => {
    if (msg.files?.some((f) => f.type.startsWith('image/'))) {
      return 'qwen2.3-vl:72b';
    }
    return 'gpt-oss:120b';
  }, []);

  const runBackgroundTasks = useCallback(async (conversation) => {
    try {
      await runSingleInference({
        model: 'gpt-oss:20b',
        messages: conversation,
        task: 'summarise',
      });
    } catch (err) {
      console.error(err);
    }
  }, []);

  const handleProactiveBehaviours = useCallback((response) => {
    const content = response?.content || '';
    if (/^\s*[-*]/m.test(content) || content.includes('|')) {
      setSavePrompt(response);
    }
    if (response?.chart) {
      renderChart(response.chart, 'chart-container');
    }
  }, []);

  const handleAssistantResponse = useCallback(
    async (response) => {
      setMessages((prev) => [...prev, response]);
      handleProactiveBehaviours(response);
      if (response?.audio) {
        await runAudioGeneration({
          model: 'stable-audio-open-1.0',
          steps: 28,
          prompt: response.audio,
        });
      }
      if (response?.speech) {
        await runTextToSpeech({ model: 'gpt-4o-mini-tts', text: response.speech });
      }
    },
    [handleProactiveBehaviours]
  );

  const sendUserMessage = useCallback(async () => {
    if (!userInput.trim() && attachments.length === 0) return;
    const userMsg = { role: 'user', content: userInput, files: attachments };
    const conversation = [...messages, userMsg];
    setMessages(conversation);
    setUserInput('');
    setAttachments([]);
    const modelToUse = detectModel(userMsg);
    abortControllerRef.current = new AbortController();
    setIsStreaming(true);
    try {
      let assistantResponse;
      if (modelToUse.startsWith('qwen')) {
        assistantResponse = await runVisionInference({
          model: modelToUse,
          messages: conversation,
          signal: abortControllerRef.current.signal,
        });
      } else {
        assistantResponse = await runSingleInference({
          model: modelToUse,
          messages: conversation,
          signal: abortControllerRef.current.signal,
        });
      }
      await handleAssistantResponse(assistantResponse);
      await runBackgroundTasks([...conversation, assistantResponse]);
      if (assistantResponse?.search) {
        const results = await runOpenAIInference({ model: 'web-search', query: assistantResponse.search });
        const distilled = await runSingleInference({
          model: 'gpt-oss:20b',
          messages: conversation.concat({ role: 'system', content: JSON.stringify(results) }),
        });
        await handleAssistantResponse(distilled);
      }
    } catch (err) {
      if (err.name !== 'AbortError') console.error(err);
    } finally {
      setIsStreaming(false);
    }
  }, [userInput, attachments, messages, detectModel, handleAssistantResponse, runBackgroundTasks]);

  const cancelRequest = useCallback(() => {
    abortControllerRef.current?.abort();
    setIsStreaming(false);
  }, []);

  const handleFileChange = useCallback((e) => {
    setAttachments(Array.from(e.target.files || []));
  }, []);

  const handleMicClick = useCallback(async () => {
    try {
      const result = await runWhisperTranscription();
      if (result?.text) setUserInput((prev) => prev + result.text);
    } catch (err) {
      console.error(err);
    }
  }, []);

  const handleVoiceClick = useCallback(async () => {
    if (!userInput.trim()) return;
    try {
      await runTextToSpeech({ model: 'gpt-4o-mini-tts', text: userInput });
    } catch (err) {
      console.error(err);
    }
  }, [userInput]);

  const saveAsSimpleNote = useCallback(async () => {
    if (!savePrompt) return;
    try {
      await runOpenAIInference({ model: 'simplenotes', content: savePrompt.content });
    } catch (err) {
      console.error(err);
    } finally {
      setSavePrompt(null);
    }
  }, [savePrompt]);

  return (
    <div className="simphoni1v-container">
      <div className="simphoni1v-top-left">
        <img src={simphoniLogo} alt="Simphoni" className="simphoni1v-logo" />
        <span className="simphoni1v-label">Simphoni 1v</span>
      </div>

      <div className="simphoni1v-header">What's on your mind today?</div>

      <div className="messages">
        {messages.map((m, idx) => (
          <div key={idx} className={`message ${m.role}`}>{m.content}</div>
        ))}
      </div>

      <div id="chart-container"></div>

      <div className="simphoni1v-input-wrapper">
        <div className="simphoni1v-input-bar">
          <button className="icon-button" onClick={() => fileInputRef.current?.click()}>
            <FaPlus />
          </button>
          <input ref={fileInputRef} type="file" multiple style={{ display: 'none' }} onChange={handleFileChange} />
          <input
            className="simphoni1v-input"
            placeholder="Ask anything"
            value={userInput}
            onChange={(e) => setUserInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && sendUserMessage()}
            disabled={isStreaming}
          />
          <button className="icon-button" onClick={handleMicClick}>
            <FaMicrophone />
          </button>
          <button className="icon-button" onClick={handleVoiceClick}>
            <FaWaveSquare />
          </button>
        </div>
      </div>

      {isStreaming && (
        <div className="cancel-wrapper">
          <button className="cancel-button" onClick={cancelRequest}>Stop</button>
        </div>
      )}

      {savePrompt && (
        <div className="save-prompt">
          <span>Save this as a SimpleNote?</span>
          <button onClick={saveAsSimpleNote}>Yes</button>
          <button onClick={() => setSavePrompt(null)}>No</button>
        </div>
      )}
    </div>
  );
}

export default Simphoni1v;

