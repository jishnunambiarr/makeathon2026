import { z } from 'zod';
import { getGrades, getMyCourses } from './tumonline.js';
import { searchRooms } from './navigatum.js';

const toolSchemas = {
  get_grades: z.object({}),
  get_my_courses: z.object({}),
  search_rooms: z.object({
    query: z.string().min(1).max(120),
  }),
};

export async function dispatchTool({ tumToken, tool, args }) {
  const schema = toolSchemas[tool];
  if (!schema) throw new Error(`unknown_tool: ${tool}`);
  const parsed = schema.safeParse(args ?? {});
  if (!parsed.success) throw new Error(`invalid_args: ${JSON.stringify(parsed.error.format())}`);

  switch (tool) {
    case 'get_grades':
      return await getGrades({ tumToken });
    case 'get_my_courses':
      return await getMyCourses({ tumToken });
    case 'search_rooms':
      return await searchRooms({ query: parsed.data.query });
    default:
      throw new Error(`unhandled_tool: ${tool}`);
  }
}

